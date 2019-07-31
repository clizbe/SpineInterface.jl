#############################################################################
# Copyright (C) 2017 - 2018  Spine Project
#
# This file is part of Spine Model.
#
# Spine Model is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Spine Model is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#############################################################################
"""
    Anything

A type with no fields that is the type of [`anything`](@ref).
"""
struct Anything
end

"""
    anything

The singleton instance of type [`Anything`](@ref), used to specify *all-pass* filters
in calls to [`RelationshipClass()`](@ref).
"""
anything = Anything()

Base.intersect(::Anything, s) = s
Base.intersect(s::T, ::Anything) where T<:AbstractArray = s
Base.intersect(s::T, ::Anything) where T<:AbstractSet = s
Base.in(item, ::Anything) = true
# Iterating `anything` returns `anything` once and then finishes
Base.iterate(::Anything) = anything, nothing
Base.iterate(::Anything, ::Nothing) = nothing
Base.show(io::IO, ::Anything) = print(io, "anything")

Broadcast.broadcastable(::Anything) = Base.RefValue{Anything}(anything)

"""
    ObjectLike

Supertype for [`Object`](@ref) and [`TimeSlice`](@ref).
"""
abstract type ObjectLike end

"""
    Object

A type for representing an object in a Spine db.
"""
struct Object <: ObjectLike
    name::Symbol
end

Object(name::AbstractString) = Object(Symbol(name))
Object(::Anything) = anything
Object(other::T) where {T<:ObjectLike} = other

# Iterate single `Object` as collection
Base.iterate(o::Object) = iterate((o,))
Base.iterate(o::Object, state::T) where T = iterate((o,), state)
Base.length(o::Object) = 1
# Compare `Object`s
Base.isless(o1::Object, o2::Object) = o1.name < o2.name


"""
    HotColdCache

A two-stage cache
"""
struct HotColdCache{K,V}
    hot::Vector{Pair{K,V}}
    cold::Vector{Pair{K,V}}
    hotlength::Int64
    function HotColdCache{K,V}(;hotlength::Int64=32) where {K,V}
        hot = Pair{K,V}[]
        cold = Pair{K,V}[]
        sizehint!(hot, hotlength)
        new(hot, cold, hotlength)
    end
end

function HotColdCache(kv::Pair{K,V}...; hotlength::Int64=32) where {K,V}
    cache = HotColdCache{K,V}(hotlength=hotlength)
    length(kv) > hotlength && sizehint!(cache.cold, length(kv) - hotlength)
    for (k, v) in kv
        cache[k] = v
    end
    cache
end

HotColdCache(kv) = HotColdCache(kv...)

Base.setindex!(cache::HotColdCache{K,V}, value::V, key::K) where {K,V} = pushfirst!(cache, key => value)

function Base.pushfirst!(cache::HotColdCache{K,V}, item::Pair{K2,V}) where {K,V,K2<:K}
    # Move last element of hot to cold if hot is 'full', then pushfirst `item` into hot
    length(cache.hot) == cache.hotlength && pushfirst!(cache.cold, pop!(cache.hot))
    pushfirst!(cache.hot, item)
end

function Base.get!(f::Function, cache::HotColdCache{K,V}, key::K2) where {K,V,K2<:K}
    # Lookup in hot first
    for (k, v) in cache.hot
        k === key && return v
    end
    # Lookup in cold. If found, move it to hot
    for (i, (k, v)) in enumerate(cache.cold)
        if k === key
            deleteat!(cache.cold, i)
            pushfirst!(cache, k => v)
            return v
        end
    end
    default = f()
    pushfirst!(cache, key => default)
    default
end

ObjectCollection = Union{Object,Vector{Object},Tuple{Vararg{Object}}}

struct ObjectClass
    name::Symbol
    default_values::NamedTuple
    object_class_names::Tuple{Vararg{Symbol}}
    objects::Array{Tuple{Object,NamedTuple},1}
    cache::HotColdCache{ObjectCollection,Vector{Int64}}
    ObjectClass(name, default_values, objects) =
        new(name, default_values, (name,), objects, HotColdCache{ObjectCollection,Vector{Int64}}())
end

ObjectClass(name) = ObjectClass(name, (), [])

struct RelationshipClass
    name::Symbol
    default_values::NamedTuple
    object_class_names::Tuple{Vararg{Symbol}}
    relationships::Array{Tuple{NamedTuple,NamedTuple},1}
    cache::HotColdCache{Dict{Symbol,ObjectCollection},Vector{Int64}}
    RelationshipClass(name, default_values, object_class_names, relationships) =
        new(name, default_values, object_class_names, relationships, HotColdCache{Dict{Symbol,ObjectCollection},Vector{Int64}}())
end

RelationshipClass(name) = RelationshipClass(name, (), [])

struct Parameter
    name::Symbol
    classes::Array{Union{ObjectClass,RelationshipClass}}
end

Parameter(name) = Parameter(name, [])

Base.show(io::IO, p::Parameter) = print(io, p.name)
Base.show(io::IO, oc::ObjectClass) = print(io, oc.name)
Base.show(io::IO, rc::RelationshipClass) = print(io, rc.name)
Base.show(io::IO, o::Object) = print(io, o.name)

# Lookup functions. These must be as optimized as possible
function lookup(oc::ObjectClass; _optimize=true, kwargs...)
    kwargs_d = Dict(pairs(kwargs)...)
    objects = nothing
    for obj_cls_name in oc.object_class_names
        obj = pop!(kwargs_d, obj_cls_name, anything)
        obj === anything || (objects = Object.(obj))
    end
    isempty(kwargs_d) || error("invalid keyword argument(s) $(keys(kwargs_d)...) for $(rc.name)")
    if objects === nothing
        oc.objects
    else
        cond(x) = first(x) in objects
        if _optimize
            indices = get!(oc.cache, objects) do
                findall(cond, oc.objects)
            end
        else
            indices = findall(cond, oc.objects)
        end
        oc.objects[indices]
    end
end

function lookup(rc::RelationshipClass; _optimize=true, kwargs...)
    kwargs_d = Dict(pairs(kwargs)...)
    objects = Dict{Symbol,ObjectCollection}()
    sizehint!(objects, length(kwargs_d))
    for obj_cls_name in rc.object_class_names
        obj = pop!(kwargs_d, obj_cls_name, anything)
        obj === anything || (objects[obj_cls_name] = Object.(obj))
    end
    isempty(kwargs_d) || error("invalid keyword argument(s) $(keys(kwargs_d)...) for $(rc.name)")
    if isempty(objects)
        rc.relationships
    else
        cond(x) = all(first(x)[k] in v for (k, v) in objects)
        if _optimize
            indices = get!(rc.cache, objects) do
                findall(cond, rc.relationships)
            end
        else
            indices = findall(cond, rc.relationships)
        end
        rc.relationships[indices]
    end
end

"""
    (<oc>::ObjectClass)(;<keyword arguments>)

An `Array` of [`Object`](@ref) instances corresponding to the objects in class `oc`.

# Arguments

For each parameter associated to `oc` in the database there is a keyword argument
named after it. The purpose is to filter the result by specific values of that parameter.

# Examples

```jldoctest
julia> using SpineInterface;

julia> url = "sqlite:///" * joinpath(dirname(pathof(SpineInterface)), "..", "examples/data/example.sqlite");

julia> using_spinedb(url)

julia> node()
5-element Array{Object,1}:
 Nimes
 Sthlm
 Leuven
 Espoo
 Dublin

julia> commodity(state_of_matter=:gas)
1-element Array{Object,1}:
 wind

```
"""
function (oc::ObjectClass)(;kwargs...)
    if length(kwargs) == 0
        first.(oc.objects)
    else
        # Return objects that match all conditions
        [obj for (obj, vals) in oc.objects if all(get(vals, p, NothingCallable())() == val for (p, val) in kwargs)]
    end
end

"""
    (<rc>::RelationshipClass)(;<keyword arguments>)

An `Array` of [`Object`](@ref) tuples corresponding to the relationships of class `rc`.

# Arguments

- For each object class in `rc` there is a keyword argument named after it.
  The purpose is to filter the result by an object or list of objects of that class,
  or to accept all objects of that class by specifying `anything` for this argument.
- `_compact::Bool=true`: whether or not filtered object classes should be removed from the resulting tuples.
- `_default=[]`: the default value to return in case no relationship passes the filter.

# Examples

```jldoctest
julia> using SpineInterface;

julia> url = "sqlite:///" * joinpath(dirname(pathof(SpineInterface)), "..", "examples/data/example.sqlite");

julia> using_spinedb(url)

julia> node__commodity()
5-element Array{NamedTuple{(:node, :commodity),Tuple{Object,Object}},1}:
 (node = Nimes, commodity = water)
 (node = Sthlm, commodity = water)
 (node = Leuven, commodity = wind)
 (node = Espoo, commodity = wind)
 (node = Dublin, commodity = wind)

julia> node__commodity(commodity=:water)
2-element Array{Object,1}:
 Nimes
 Sthlm

julia> node__commodity(node=(:Dublin, :Espoo))
1-element Array{Object,1}:
 wind

julia> node__commodity(node=anything)
2-element Array{Object,1}:
 water
 wind

julia> node__commodity(commodity=:water, _compact=false)
2-element Array{NamedTuple{(:node, :commodity),Tuple{Object,Object}},1}:
 (node = Nimes, commodity = water)
 (node = Sthlm, commodity = water)

julia> node__commodity(commodity=:gas, _default=:nogas)
:nogas

```
"""
function (rc::RelationshipClass)(;_compact=true, _default=[], _optimize=true, kwargs...)
    if _compact
        head = Tuple(x for x in rc.object_class_names if !(x in keys(kwargs)))
    else
        head = rc.object_class_names
    end
    if isempty(head)
        result = []
    else
        result = first.(lookup(rc; _optimize=_optimize, kwargs...))
    end
    if isempty(result)
        _default
    elseif head == rc.object_class_names
        result
    elseif length(head) == 1
        unique(x[head...] for x in result)
    else
        unique(NamedTuple{head}([x[k] for k in head]) for x in result)
    end
end

"""
    (<p>::Parameter)(;<keyword arguments>)

The value of parameter `p` for a given object or relationship.

# Arguments

- For each object class associated with `p` there is a keyword argument named after it.
  The purpose is to retrieve the value of `p` for a specific object.
- For each relationship class associated with `p`, there is a keyword argument named after each of the
  object classes involved in it. The purpose is to retrieve the value of `p` for a specific relationship.
- `i::Int64`: a specific index to retrieve in case of an array value (ignored otherwise).
- `t::TimeSlice`: a specific time-index to retrieve in case of a time-varying value (ignored otherwise).


# Examples

```jldoctest
julia> using SpineInterface;

julia> url = "sqlite:///" * joinpath(dirname(pathof(SpineInterface)), "..", "examples/data/example.sqlite");

julia> using_spinedb(url)

julia> tax_net_flow(node=:Sthlm, commodity=:water)
4

julia> demand(node=:Sthlm, i=1)
21

```
"""
function (p::Parameter)(;_optimize=true, kwargs...)
    for class in p.classes
        base_kwargs = Dict()
        extra_kwargs = Dict()
        for (keyword, arg) in kwargs
            if keyword in class.object_class_names
                base_kwargs[keyword] = arg
            else
                extra_kwargs[keyword] = arg
            end
        end
        length(base_kwargs) == length(class.object_class_names) || continue
        match = lookup(class; _optimize=_optimize, base_kwargs...)
        length(match) == 1 || continue
        x, values = first(match)
        value = get(values, p.name, class.default_values[p.name])
        return value(;extra_kwargs...)
    end
    error("'$p' is not specified for the given arguments $(kwargs...)")
end
