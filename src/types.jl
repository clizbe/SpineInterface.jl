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
Base.intersect(s, ::Anything) = s
Base.show(io::IO, ::Anything) = print(io, "anything")
Base.in(item, ::Anything) = true
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
Object(other::Object) = other

# Iterate single `Object` as collection
Base.iterate(o::Object) = iterate((o,))
Base.iterate(o::Object, state::T) where T = iterate((o,), state)
Base.length(o::Object) = 1
# Compare `Object`s
Base.isless(o1::Object, o2::Object) = o1.name < o2.name

struct ObjectClass
    name::Symbol
    objects::Array{Object,1}
    object_subset_dict::Dict{Symbol,Any}
end

ObjectClass(name) = ObjectClass(name, [], Dict())

struct RelationshipClass{N,K,V}
    name::Symbol
    obj_cls_name_tuple::NTuple{N,Symbol}
    object_tuples::Array{NamedTuple{K,V},1}
    obj_type_dict::Dict{Symbol,Type}
    cache::Array{Pair,1}
end

function RelationshipClass(
        name,
        obj_cls_name_tuple::NTuple{N,Symbol},
        object_tuples::Array{NamedTuple{K,V},1}
    ) where {N,K,V<:Tuple}
    K == obj_cls_name_tuple || error("$K and $obj_cls_name_tuple do not match")
    obj_type_dict = Dict(zip(K, V.parameters))
    RelationshipClass{N,K,V}(name, obj_cls_name_tuple, object_tuples, obj_type_dict, Array{Pair,1}())
end

function RelationshipClass(
        name,
        obj_cls_name_tuple::NTuple{N,Symbol},
        object_tuples::Array{NamedTuple{K,V} where V<:Tuple,1}
    ) where {N,K}
    K == obj_cls_name_tuple || error("$K and $obj_cls_name_tuple do not match")
    obj_type_dict = Dict(k => Object for k in K)
    V = NTuple{N,Object}
    RelationshipClass{N,K,V}(name, obj_cls_name_tuple, object_tuples, obj_type_dict, Array{Pair,1}())
end

RelationshipClass(name) = RelationshipClass(name, (), [], Dict(), [])

struct Parameter
    name::Symbol
    class_values::Dict{Tuple,Any}
end

Parameter(name) = RelationshipClass(name, Dict())

Base.show(io::IO, p::Parameter) = print(io, p.name)
Base.show(io::IO, oc::ObjectClass) = print(io, oc.name)
Base.show(io::IO, rc::RelationshipClass) = print(io, rc.name)
Base.show(io::IO, o::Object) = print(io, o.name)

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
1-element Array{Any,1}:
 wind

```
"""
function (oc::ObjectClass)(;kwargs...)
    if length(kwargs) == 0
        oc.objects
    else
        # Return the object subset at the intersection of all kwargs
        object_subset = []
        for (par, val) in kwargs
            !haskey(oc.object_subset_dict, par) && error("'$par' is not a list-parameter for '$oc'")
            d = oc.object_subset_dict[par]
            objs = []
            for v in ScalarValue.(val)
                obj = get(d, v, nothing)
                if obj == nothing
                    @warn("'$v' is not a listed value for '$par' as defined for class '$oc'")
                else
                    append!(objs, obj)
                end
            end
            if isempty(object_subset)
                object_subset = objs
            else
                object_subset = [x for x in object_subset if x in objs]
            end
        end
        object_subset
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
 (node = Dublin, commodity = wind)
 (node = Espoo, commodity = wind)
 (node = Leuven, commodity = wind)
 (node = Nimes, commodity = water)
 (node = Sthlm, commodity = water)

julia> node__commodity(commodity=:water)
2-element Array{Object,1}:
 Nimes
 Sthlm

julia> node__commodity(node=(:Dublin, :Espoo))
1-element Array{Object,1}:
 wind

julia> node__commodity(node=anything)
2-element Array{Object,1}:
 wind
 water

julia> node__commodity(commodity=:water, _compact=false)
2-element Array{NamedTuple{(:node, :commodity),Tuple{Object,Object}},1}:
 (node = Nimes, commodity = water)
 (node = Sthlm, commodity = water)

julia> node__commodity(commodity=:gas, _default=:nogas)
:nogas

```
"""
function (rc::RelationshipClass)(;_compact=true, _default=[], _optimize=true, kwargs...)
    new_kwargs = Dict()
    tail = []
    for (obj_cls_name, obj) in kwargs
        !(obj_cls_name in rc.obj_cls_name_tuple) && error(
            "'$obj_cls_name' is not a member of '$rc' (valid members are '$(join(rc.obj_cls_name_tuple, "', '"))')"
        )
        push!(tail, obj_cls_name)
        if obj != anything
            push!(new_kwargs, obj_cls_name => rc.obj_type_dict[obj_cls_name].(obj))
        end
    end
    head = if _compact
        Tuple(x for x in rc.obj_cls_name_tuple if !(x in tail))
    else
        rc.obj_cls_name_tuple
    end
    result = if isempty(head)
        []
    elseif _optimize
        indices = pull!(rc.cache, new_kwargs, nothing)
        if indices === nothing
            cond(x) = all(x[k] in v for (k, v) in new_kwargs)
            # TODO: Check if there's any benefit from having `object_tuples` sorted here
            indices = findall(cond, rc.object_tuples)
            pushfirst!(rc.cache, new_kwargs => indices)
        end
        rc.object_tuples[indices]
    else
        [x for x in rc.object_tuples if all(x[k] in v for (k, v) in new_kwargs)]
    end
    if isempty(result)
        _default
    elseif head == rc.obj_cls_name_tuple
        result
    elseif length(head) == 1
        unique(x[head...] for x in result)
    else
        unique(NamedTuple{head}([x[k] for k in head]) for x in result)
    end
end

"""
    (<p>::Parameter)(;<keyword arguments>)

The values of parameter `p`. They are given as a `Dict` mapping object and relationship classes
associated with `p`, to another `Dict` mapping corresponding objects or relationships to values.

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
    if length(kwargs) == 0
        # Return dict if kwargs is empty
        p.class_values
    else
        kwkeys = keys(kwargs)
        class_names = getsubkey(p.class_values, kwkeys, nothing)
        class_names == nothing && error("can't find a definition of '$p' for '$kwkeys'")
        parameter_value_pairs = p.class_values[class_names]
        kwvalues = values(kwargs)
        object_tuple = Object.(Tuple([kwvalues[k] for k in class_names]))
        value = if _optimize
            pull!(parameter_value_pairs, object_tuple, nothing)
        else
            i = findfirst(x -> first(x) == object_tuple, parameter_value_pairs)
            if i === nothing
                nothing
            else
                last(parameter_value_pairs[i])
            end
        end
        value === nothing && error("'$p' not specified for '$object_tuple'")
        extra_kwargs = Dict(k => v for (k, v) in kwargs if !(k in class_names))
        value(;extra_kwargs...)
    end
end