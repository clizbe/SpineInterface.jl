#############################################################################
# Copyright (C) 2017 - 2018  Spine Project
#
# This file is part of SpineInterface.
#
# SpineInterface is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# SpineInterface is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#############################################################################

"""
    anything

The singleton instance of type [`Anything`](@ref), used to specify *all-pass* filters
in calls to [`RelationshipClass()`](@ref).
"""
anything = Anything()

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


julia> sort(node())
5-element Array{Object,1}:
 Dublin
 Espoo
 Leuven
 Nimes
 Sthlm

julia> commodity(state_of_matter=commodity(:gas))
1-element Array{Object,1}:
 wind
```
"""
function (oc::ObjectClass)(; kwargs...)
    isempty(kwargs) && return oc.objects
    function cond(o)
        for (p, v) in kwargs
            value = get(oc.parameter_values[o], p, get(oc.parameter_defaults, p, nothing))
            (value !== nothing && value() === v) || return false
        end
        true
    end
    filter(cond, oc.objects)
end
function (oc::ObjectClass)(name::Symbol)
    i = findfirst(o -> o.name == name, oc.objects)
    i != nothing && return oc.objects[i]
    nothing
end
(oc::ObjectClass)(name::String) = oc(Symbol(name))

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


julia> sort(node__commodity())
5-element Array{NamedTuple,1}:
 (node = Dublin, commodity = wind)
 (node = Espoo, commodity = wind)
 (node = Leuven, commodity = wind)
 (node = Nimes, commodity = water)
 (node = Sthlm, commodity = water)

julia> node__commodity(commodity=commodity(:water))
2-element Array{Object,1}:
 Nimes
 Sthlm

julia> node__commodity(node=(node(:Dublin), node(:Espoo)))
1-element Array{Object,1}:
 wind

julia> sort(node__commodity(node=anything))
2-element Array{Object,1}:
 water
 wind

julia> sort(node__commodity(commodity=commodity(:water), _compact=false))
2-element Array{NamedTuple,1}:
 (node = Nimes, commodity = water)
 (node = Sthlm, commodity = water)

julia> node__commodity(commodity=commodity(:gas), _default=:nogas)
:nogas
```
"""
function (rc::RelationshipClass)(; _compact::Bool=true, _default::Any=[], kwargs...)
    isempty(kwargs) && return rc.relationships
    relationships = if !_compact
        _find_rels(rc; kwargs...)
    else
        object_class_names = setdiff(rc.object_class_names, keys(kwargs))
        if isempty(object_class_names)
            []
        elseif length(object_class_names) == 1
            unique(rel[object_class_names[1]] for rel in _find_rels(rc; kwargs...))
        else
            unique(
                (; zip(object_class_names, (rel[k] for k in object_class_names))...)
                for rel in _find_rels(rc; kwargs...)
            )
        end
    end
    if !isempty(relationships)
        relationships
    else
        _default
    end
end

_find_rels(rc; kwargs...) = _find_rels(rc, _find_rows(rc; kwargs...))
_find_rels(rc, rows) = (rc.relationships[row] for row in rows)
_find_rels(rc, ::Anything) = rc.relationships

function _find_rows(rc; kwargs...)
    memoized_rows = get!(rc.row_map, rc.name, Dict())
    get!(memoized_rows, kwargs) do
        _do_find_rows(rc; kwargs...)
    end
end

function _do_find_rows(rc; kwargs...)
    rows = anything
    for (oc_name, objs) in kwargs
        oc_row_map = get(rc.row_map, oc_name, nothing)
        oc_row_map === nothing && return []
        oc_rows = _oc_rows(rc, oc_row_map, objs)
        oc_rows === anything && continue
        if rows === anything
            rows = collect(oc_rows)
        else
            intersect!(rows, oc_rows)
        end
        isempty(rows) && return []
    end
    rows
end

_oc_rows(_rc, oc_row_map, objs) = (row for obj in objs for row in get(oc_row_map, obj, ()))
_oc_rows(rc, _oc_row_map, ::Anything) = anything
_oc_rows(rc, _oc_row_map, ::Nothing) = []

"""
    (<p>::Parameter)(;<keyword arguments>)

The value of parameter `p` for a given arguments.

# Arguments

  - For each object class associated with `p` there is a keyword argument named after it.
    The purpose is to retrieve the value of `p` for a specific object.
  - For each relationship class associated with `p`, there is a keyword argument named after each of the
    object classes involved in it. The purpose is to retrieve the value of `p` for a specific relationship.
  - `i::Int64`: a specific index to retrieve in case of an array value (ignored otherwise).
  - `t::TimeSlice`: a specific time-index to retrieve in case of a time-varying value (ignored otherwise).
  - `inds`: indexes for navigating a `Map` (ignored otherwise). Tuples correspond to navigating nested `Maps`.
  - `_strict::Bool`: whether to raise an error or return `nothing` if the parameter is not specified for the given arguments.

# Examples

```jldoctest
julia> using SpineInterface;


julia> url = "sqlite:///" * joinpath(dirname(pathof(SpineInterface)), "..", "examples/data/example.sqlite");


julia> using_spinedb(url)


julia> tax_net_flow(node=node(:Sthlm), commodity=commodity(:water))
4

julia> demand(node=node(:Sthlm), i=1)
21
```
"""
function (p::Parameter)(; _strict=true, _default=nothing, kwargs...)
    pv_new_kwargs = _split_parameter_value_kwargs(p; _strict=_strict, _default=_default, kwargs...)
    if !isnothing(pv_new_kwargs)
        pv, new_kwargs = pv_new_kwargs
        pv(; new_kwargs...)
    else
        _default
    end
end

"""
    (<pv>::ParameterValue)(upd; <keyword arguments>)

A value from `pv`.
"""
function (pv::ParameterValue)(upd=nothing; kwargs...) end

# _Scalar
(pv::ParameterValue{T} where T<:_Scalar)(upd=nothing; kwargs...) = pv.value
(pv::ParameterValue{T} where T<:Array)(upd=nothing; i::Union{Int64,Nothing}=nothing, kwargs...) = _get_value(pv, i)
function (pv::ParameterValue{T} where T<:TimePattern)(
    upd=nothing; t::Union{DateTime,TimeSlice,Nothing}=nothing, kwargs...
)
    _get_value(pv, t, upd)
end
function (pv::ParameterValue{T} where T<:TimeSeries)(
    upd=nothing; t::Union{DateTime,TimeSlice,Nothing}=nothing, kwargs...
)
    _get_value(pv, t, upd)
end
function (pv::ParameterValue{T} where {T<:Map})(upd=nothing; t=nothing, i=nothing, kwargs...)
    isempty(kwargs) && return _recursive_inner_value(pv.value)
    arg = first(values(kwargs))
    new_kwargs = Base.tail((; kwargs...))
    _recursive_inner_value(_get_value(pv, arg, upd; t=t, i=i, new_kwargs...))
end

_recursive_inner_value(x) = x
_recursive_inner_value(x::ParameterValue) = _recursive_inner_value(x.value)
function _recursive_inner_value(x::Map)
    Map(x.indexes, _recursive_inner_value.(x.values))
end

# Array
_get_value(pv::ParameterValue{T}, ::Nothing) where T<:Array = pv.value
_get_value(pv::ParameterValue{T}, i::Int64) where T<:Array = get(pv.value, i, nothing)
# TimePattern
_get_value(pv::ParameterValue{T}, ::Nothing, upd) where T<:TimePattern = pv.value
function _get_value(pv::ParameterValue{T}, t::DateTime, upd) where T<:TimePattern
    _get_value(pv, TimeSlice(t, t), upd)
end
function _get_value(pv::ParameterValue{T}, t::TimeSlice, upd) where T<:TimePattern
    vals = [val for (tp, val) in pv.value if overlaps(t, tp)]
    if upd !== nothing
        timeout = if isempty(vals)
            Second(0)
        else
            min(
                floor(start(t), pv.precision) + pv.precision(1) - start(t),
                ceil(end_(t), pv.precision) + Millisecond(1) - end_(t)
            )
        end
        _add_update(t, timeout, upd)
    end
    isempty(vals) && return NaN
    mean(vals)
end
# TimeSeries
_get_value(pv::ParameterValue{T}, ::Nothing, upd) where T<:TimeSeries = pv.value
function _get_value(pv::ParameterValue{T}, t, upd) where T<:TimeSeries
    if pv.value.repeat
        _get_repeating_time_series_value(pv, t, upd)
    else
        _get_time_series_value(pv, t, upd)
    end
end
function _get_time_series_value(pv, t::DateTime, upd)
    pv.value.ignore_year && (t -= Year(t))
    t < pv.value.indexes[1] && return NaN
    t > pv.value.indexes[end] && !pv.value.ignore_year && return NaN
    pv.value.values[max(1, searchsortedlast(pv.value.indexes, t))]
end
function _get_time_series_value(pv, t::TimeSlice, upd)
    adjusted_t = pv.value.ignore_year ? t - Year(start(t)) : t
    t_start, t_end = start(adjusted_t), end_(adjusted_t)
    a, b = _search_overlap(pv.value, t_start, t_end)
    if upd !== nothing
        timeout = _timeout(pv.value, t_start, t_end, a, b)
        _add_update(t, timeout, upd)
    end
    t_end <= pv.value.indexes[1] && return NaN
    t_start > pv.value.indexes[end] && !pv.value.ignore_year && return NaN
    mean(Iterators.filter(!isnan, pv.value.values[a:b]))
end
function _get_repeating_time_series_value(pv, t::DateTime, upd)
    pv.value.ignore_year && (t -= Year(t))
    mismatch = t - pv.value.indexes[1]
    reps = fld(mismatch, pv.span)
    t -= reps * pv.span
    pv.value.values[max(1, searchsortedlast(pv.value.indexes, t))]
end
function _get_repeating_time_series_value(pv, t::TimeSlice, upd)
    adjusted_t = pv.value.ignore_year ? t - Year(start(t)) : t
    t_start = start(adjusted_t)
    t_end = end_(adjusted_t)
    mismatch_start = t_start - pv.value.indexes[1]
    mismatch_end = t_end - pv.value.indexes[1]
    reps_start = fld(mismatch_start, pv.span)
    reps_end = fld(mismatch_end, pv.span)
    t_start -= reps_start * pv.span
    t_end -= reps_end * pv.span
    a, b = _search_overlap(pv.value, t_start, t_end)
    if upd !== nothing
        timeout = _timeout(pv.value, t_start, t_end, a, b)
        _add_update(t, timeout, upd)
    end
    reps = reps_end - reps_start
    reps == 0 && return mean(Iterators.filter(!isnan, pv.value.values[a:b]))
    avals = pv.value.values[a:end]
    bvals = pv.value.values[1:b]
    asum = sum(Iterators.filter(!isnan, avals))
    bsum = sum(Iterators.filter(!isnan, bvals))
    alen = count(!isnan, avals)
    blen = count(!isnan, bvals)
    (asum + bsum + (reps - 1) * pv.valsum) / (alen + blen + (reps - 1) * pv.len)
end
# Map
function _get_value(pv::ParameterValue{T}, k, upd; kwargs...) where {T<:Map}
    i = _search_equal(pv.value.indexes, k)
    i === nothing && return pv(upd; kwargs...)
    pv.value.values[i](upd; kwargs...)
end
function _get_value(pv::ParameterValue{T}, o::ObjectLike, upd; kwargs...) where {V,T<:Map{Symbol,V}}
    i = _search_equal(pv.value.indexes, o.name)
    i === nothing && return pv(upd; kwargs...)
    pv.value.values[i](upd; kwargs...)
end
function _get_value(pv::ParameterValue{T}, x::K, upd; kwargs...) where {V,K<:Union{DateTime,Float64},T<:Map{K,V}}
    i = _search_nearest(pv.value.indexes, x)
    i === nothing && return pv(upd; kwargs...)
    pv.value.values[i](upd; kwargs...)
end
function _get_value(pv::ParameterValue{T}, s::_StartRef, upd; kwargs...) where {V,T<:Map{DateTime,V}}
    t = s.time_slice
    i = _search_nearest(pv.value.indexes, start(t))
    if upd !== nothing
        timeout = i === nothing ? Second(0) : _next_index(pv.value, i) - start(t)
        _add_update(s.time_slice, timeout, upd)
    end
    i === nothing && return pv(upd; kwargs...)
    pv.value.values[i](upd; kwargs...)
end

function _search_overlap(ts::TimeSeries, t_start::DateTime, t_end::DateTime)
    a = if t_start < ts.indexes[1]
        1
    elseif t_start > ts.indexes[end]
        length(ts.indexes)
    else
        searchsortedlast(ts.indexes, t_start)
    end
    b = searchsortedfirst(ts.indexes, t_end) - 1
    (a, b)
end

function _search_equal(arr::AbstractArray{T,1}, x::T) where {T}
    i = searchsortedfirst(arr, x)  # index of the first value in arr greater than or equal to x, length(arr) + 1 if none
    i <= length(arr) && arr[i] === x && return i
    nothing
end
_search_equal(arr, x) = nothing

function _search_nearest(arr::AbstractArray{T,1}, x::T) where {T}
    i = searchsortedlast(arr, x)  # index of the last value in arr less than or equal to x, 0 if none
    max(i, 1)
end
_search_nearest(arr, x) = nothing

_next_index(val::Union{TimeSeries,Map}, pos) = val.indexes[min(pos + 1, length(val.indexes))]

function _timeout(val::TimeSeries, t_start, t_end, a, b)
    min(_next_index(val, a) - t_start, _next_index(val, b) + Millisecond(1) - t_end)
end

members(::Anything) = anything
members(x) = unique(member for obj in x for member in obj.members)

groups(x) = unique(group for obj in x for group in obj.groups)

"""
    indices(p::Parameter; kwargs...)

An iterator over all objects and relationships where the value of `p` is different than `nothing`.

# Arguments

  - For each object class where `p` is defined, there is a keyword argument named after it;
    similarly, for each relationship class where `p` is defined, there is a keyword argument
    named after each object class in it.
    The purpose of these arguments is to filter the result by an object or list of objects of an specific class,
    or to accept all objects of that class by specifying `anything` for the corresponding argument.

# Examples

```jldoctest
julia> using SpineInterface;


julia> url = "sqlite:///" * joinpath(dirname(pathof(SpineInterface)), "..", "examples/data/example.sqlite");


julia> using_spinedb(url)


julia> collect(indices(tax_net_flow))
1-element Array{NamedTuple{(:commodity, :node),Tuple{Object,Object}},1}:
 (commodity = water, node = Sthlm)

julia> collect(indices(demand))
5-element Array{Object,1}:
 Nimes
 Sthlm
 Leuven
 Espoo
 Dublin
```
"""
function indices(p::Parameter; kwargs...)
    (
        ent
        for class in p.classes
        for ent in _entities(class; kwargs...)
        if _get(class.parameter_values[_entity_key(ent)], p.name, class.parameter_defaults)() !== nothing
    )
end

"""
    indices_as_tuples(p::Parameter; kwargs...)

Like `indices` but also yields tuples for single-dimensional entities.
"""
function indices_as_tuples(p::Parameter; kwargs...)
    (
        _entity_tuple(ent, class)
        for class in p.classes
        for ent in _entities(class; kwargs...)
        if _get(class.parameter_values[_entity_key(ent)], p.name, class.parameter_defaults)() !== nothing
    )
end

"""
    maximum_parameter_value(p::Parameter)

The singe maximum value of a `Parameter` across all its `ObjectClasses` or `RelationshipClasses`
for any`ParameterValue` types.
"""
function maximum_parameter_value(p::Parameter)
    pvs = (
        first(_split_parameter_value_kwargs(p; ent_tup...)) for class in p.classes for ent_tup in _entity_tuples(class)
    )
    pvs_skip_nothing = (pv for pv in pvs if pv() !== nothing)
    isempty(pvs_skip_nothing) && return nothing
    maximum(_maximum_parameter_value(pv) for pv in pvs_skip_nothing)
end

_entities(class::ObjectClass; kwargs...) = class()
_entities(class::RelationshipClass; kwargs...) = class(; _compact=false, kwargs...)

_entity_key(o::ObjectLike) = o
_entity_key(r::RelationshipLike) = tuple(r...)

_entity_tuple(o::ObjectLike, class) = (; (class.name => o,)...)
_entity_tuple(r::RelationshipLike, class) = r

_entity_tuples(class::ObjectClass; kwargs...) = (_entity_tuple(o, class) for o in class())
_entity_tuples(class::RelationshipClass; kwargs...) = class(; _compact=false, kwargs...)

# Enable comparing Month and Year with all the other period types for computing the maximum parameter value
_upper_bound(p) = p
_upper_bound(p::Month) = p.value * Day(31)
_upper_bound(p::Year) = p.value * Day(366)

# FIXME: We need to handle empty collections here
_maximum_skipnan(itr) = maximum(x -> isnan(x) ? -Inf : _upper_bound(x), itr)

_maximum_parameter_value(pv::ParameterValue{T}) where T<:Array = _maximum_skipnan(pv.value)
function _maximum_parameter_value(pv::ParameterValue{T}) where T<:Union{TimePattern,TimeSeries}
    _maximum_skipnan(values(pv.value))
end
function _maximum_parameter_value(pv::ParameterValue{T}) where T<:Map
    _maximum_skipnan(_maximum_parameter_value.(values(pv.value)))
end
_maximum_parameter_value(pv::ParameterValue) = _upper_bound(pv.value)

"""
    add_objects!(object_class, objects)

Remove from `objects` everything that's already in `object_class`, and append the rest.
Return the modified `object_class`.
"""
function add_objects!(object_class::ObjectClass, objects::Array)
    setdiff!(objects, object_class.objects)
    append!(object_class.objects, objects)
    merge!(object_class.parameter_values, Dict(obj => Dict() for obj in objects))
    object_class
end

function add_object_parameter_values!(object_class::ObjectClass, parameter_values::Dict; merge_values=false)
    add_objects!(object_class, collect(keys(parameter_values)))
    do_merge! = merge_values ? mergewith!(merge!) : merge!
    for (obj, vals) in parameter_values
        do_merge!(object_class.parameter_values[obj], vals)
    end
end

function add_object_parameter_defaults!(object_class::ObjectClass, parameter_defaults::Dict; merge_values=false)
    do_merge! = merge_values ? mergewith!(merge!) : merge!
    do_merge!(object_class.parameter_defaults, parameter_defaults)
end

function add_object!(object_class::ObjectClass, object::ObjectLike)
    add_objects!(object_class, [object])
end

"""
    add_relationships!(relationship_class, relationships)

Remove from `relationships` everything that's already in `relationship_class`, and append the rest.
Return the modified `relationship_class`.
"""
function add_relationships!(relationship_class::RelationshipClass, object_tuples::Vector{T}) where T<:ObjectTupleLike
    relationships = [(; zip(relationship_class.object_class_names, obj_tup)...) for obj_tup in object_tuples]
    add_relationships!(relationship_class, relationships)
end
function add_relationships!(relationship_class::RelationshipClass, relationships::Vector)
    relationships = setdiff(relationships, relationship_class.relationships)
    _append_relationships!(relationship_class, relationships)
    merge!(relationship_class.parameter_values, Dict(values(rel) => Dict() for rel in relationships))
    relationship_class
end

function add_relationship_parameter_values!(
    relationship_class::RelationshipClass, parameter_values::Dict; merge_values=false
)
    add_relationships!(relationship_class, collect(keys(parameter_values)))
    do_merge! = merge_values ? mergewith!(merge!) : merge!
    for (rel, vals) in parameter_values
        obj_tup = values(rel)
        do_merge!(relationship_class.parameter_values[obj_tup], vals)
    end
end

function add_relationship_parameter_defaults!(
    relationship_class::RelationshipClass, parameter_defaults::Dict; merge_values=false
)
    do_merge! = merge_values ? mergewith!(merge!) : merge!
    do_merge!(relationship_class.parameter_defaults, parameter_defaults)
end

function add_relationship!(relationship_class::RelationshipClass, relationship::RelationshipLike)
    add_relationships!(relationship_class, [relationship])
end

"""
    object_classes(m=@__MODULE__)

A sequence of `ObjectClass`es generated by `using_spinedb` in the given module.
"""
object_classes(m=@__MODULE__) = _active_values(m, :_spine_object_classes)

"""
    relationship_classes(m=@__MODULE__)

A sequence of `RelationshipClass`es generated by `using_spinedb` in the given module.
"""
relationship_classes(m=@__MODULE__) = _active_values(m, :_spine_relationship_classes)

"""
    parameters(m=@__MODULE__)

A sequence of `Parameter`s generated by `using_spinedb` in the given module.
"""
parameters(m=@__MODULE__) = _active_values(m, :_spine_parameters)

"""
    object_class(name, m=@__MODULE__)

The `ObjectClass` of given name, generated by `using_spinedb` in the given module.
"""
object_class(name, m=@__MODULE__) = _active_value(m, :_spine_object_classes, name)

"""
    relationship_class(name, m=@__MODULE__)

The `RelationshipClass` of given name, generated by `using_spinedb` in the given module.
"""
relationship_class(name, m=@__MODULE__) = _active_value(m, :_spine_relationship_classes, name)

"""
    parameter(name, m=@__MODULE__)

The `Parameter` of given name, generated by `using_spinedb` in the given module.
"""
parameter(name, m=@__MODULE__) = _active_value(m, :_spine_parameters, name)

_active_values(m, set_name) = [x for x in values(_getproperty(m, set_name, Dict())) if _is_active(x)]

function _active_value(m, set_name, name)
    val = get(_getproperty(m, set_name, Dict()), name, nothing)
    _is_active(val) ? val : nothing
end

_is_active(x) = haskey(x.env_dict, _active_env())
_is_active(::Nothing) = false

"""
    difference(left, right)

A string summarizing the differences between the `left` and the right `Dict`s.
Both `left` and `right` are mappings from string to an array.
"""
function difference(left, right)
    diff = OrderedDict(
        "object classes" => setdiff(first.(left["object_classes"]), first.(right["object_classes"])),
        "relationship classes" => setdiff(first.(left["relationship_classes"]), first.(right["relationship_classes"])),
        "parameters" => setdiff(
            (x -> x[2]).(vcat(left["object_parameters"], left["relationship_parameters"])),
            (x -> x[2]).(vcat(right["object_parameters"], right["relationship_parameters"])),
        ),
    )
    header_size = maximum(length(key) for key in keys(diff))
    empty_header = repeat(" ", header_size)
    splitter = repeat(" ", 2)
    diff_str = ""
    for (key, value) in diff
        isempty(value) && continue
        header = lpad(key, header_size)
        diff_str *= "\n" * string(header, splitter, value[1], "\n")
        diff_str *= join([string(empty_header, splitter, x) for x in value[2:end]], "\n") * "\n"
    end
    diff_str
end

"""
    realize(call)

Perform the given call and return the result.
"""
function realize(call, upd=nothing)
    try
        _do_realize(call, upd)
    catch e
        err_msg = "unable to evaluate expression:\n\t$call\n"
        rethrow(ErrorException("$err_msg$(sprint(showerror, e))"))
    end
end

function add_dimension!(cls::RelationshipClass, name::Symbol, obj)
    push!(cls.object_class_names, name)
    push!(cls.intact_object_class_names, name)
    map!(rel -> (; rel..., Dict(name => obj)...), cls.relationships, cls.relationships)
    for rel in collect(keys(cls.parameter_values))
        new_rel = (rel..., obj)
        cls.parameter_values[new_rel] = pop!(cls.parameter_values, rel)
    end
    cls.row_map[name] = Dict(obj => collect(1:length(cls.relationships)))
    delete!(cls.row_map, cls.name)  # delete memoized rows
    nothing
end

const __active_env = Ref(:base)

function _activate_env(env::Symbol)
    __active_env[] = env
end

_active_env() = __active_env[]

function with_env(f::Function, env::Symbol)
    prev_env = _active_env()
    _activate_env(env)
    try
        f()
    finally
        _activate_env(prev_env)
    end
end