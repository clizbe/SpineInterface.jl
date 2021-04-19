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
    AbstractParameterValue

Supertype for all parameter value callables.
"""
abstract type AbstractParameterValue end

abstract type AbstractTimeSeriesParameterValue <: AbstractParameterValue end

abstract type Call end

"""
    Anything

A type with no fields that is the type of [`anything`](@ref).
"""
struct Anything end

"""
    Object

A type for representing an object in a Spine db.
"""
struct Object
    name::Symbol
    id::UInt64
    members::Array{Object,1}
    groups::Array{Object,1}
end

"""
    TimeSlice

A type for representing a slice of time.
"""
struct TimeSlice
    start::Ref{DateTime}
    end_::Ref{DateTime}
    duration::Float64
    blocks::NTuple{N,Object} where {N}
    id::UInt64
    function TimeSlice(start, end_, duration, blocks)
        start > end_ && error("out of order")
        id = objectid((start, end_, duration, blocks))
        new(Ref(start), Ref(end_), duration, blocks, id)
    end
end

ObjectLike = Union{Object,TimeSlice,Int64}

RelationshipLike{K} = NamedTuple{K,V} where {K,V<:Tuple{Vararg{ObjectLike}}}

struct ObjectIdFactory
    max_object_id::Ref{UInt64}
    ObjectIdFactory(i) = new(Ref(i))
end

struct ObjectClass
    name::Symbol
    objects::Array{ObjectLike,1}
    parameter_values::Dict{ObjectLike,Dict{Symbol,AbstractParameterValue}}
    parameter_defaults::Dict{Symbol,AbstractParameterValue}
    ObjectClass(name, objects, vals=Dict(), defaults=Dict()) = new(name, objects, vals, defaults)
end

struct RelationshipClass
    name::Symbol
    object_class_names::Array{Symbol,1}
    relationships::Array{RelationshipLike,1}
    parameter_values::Dict{Tuple{Vararg{ObjectLike}},Dict{Symbol,AbstractParameterValue}}
    intact_object_class_names::Array{Symbol,1}
    parameter_defaults::Dict{Symbol,AbstractParameterValue}
    lookup_cache::Dict{Bool,Dict}
    RelationshipClass(name, cls_names, rels, vals=Dict(), intact_cls_names=cls_names, defaults=Dict()) =
        new(name, cls_names, rels, vals, intact_cls_names, defaults, Dict(:true => Dict(), :false => Dict()))
end

struct Parameter
    name::Symbol
    classes::Array{Union{ObjectClass,RelationshipClass},1}
    Parameter(name, classes=[]) = new(name, classes)
end

# parameter value types
# types returned by the parsing function `spinedb_api.from_database`
# are automatically converted to these using `PyCall.pytype_mapping` as defined in the module's __init__ method.
# This allows us to mutiple dispatch `parameter_value`
"""
    PeriodCollection
"""
struct PeriodCollection
    Y::Union{Array{UnitRange{Int64},1},Nothing}
    M::Union{Array{UnitRange{Int64},1},Nothing}
    D::Union{Array{UnitRange{Int64},1},Nothing}
    WD::Union{Array{UnitRange{Int64},1},Nothing}
    h::Union{Array{UnitRange{Int64},1},Nothing}
    m::Union{Array{UnitRange{Int64},1},Nothing}
    s::Union{Array{UnitRange{Int64},1},Nothing}
    function PeriodCollection(; Y=nothing, M=nothing, D=nothing, WD=nothing, h=nothing, m=nothing, s=nothing)
        new(Y, M, D, WD, h, m, s)
    end
end

TimePattern = Dict{PeriodCollection,T} where {T}

struct TimeSeries{V}
    indexes::Array{DateTime,1}
    values::Array{V,1}
    ignore_year::Bool
    repeat::Bool
    function TimeSeries(inds, vals::Array{V,1}, iy, rep) where {V}
        sorted_inds, sorted_vals = _sort_inds_vals(inds, vals)
        new{V}(sorted_inds, sorted_vals, iy, rep)
    end
end

"""
    Map{K,V}

A nested general purpose indexed value corresponding to the similarly named `spinedb_api` class.

Consists of an `Array` of indexes and an `Array` of values.
See `MapParameterValue` for the corresponding `AbstractParameterValue` type for accessing `Map` type
parameters.
"""
struct Map{K,V}
    indexes::Array{K,1}
    values::Array{V,1}
    function Map(inds::Array{K,1}, vals::Array{V,1}) where {K,V}
        sorted_inds, sorted_vals = _sort_inds_vals(inds, vals)
        new{K,V}(sorted_inds, sorted_vals)
    end
end

# AbstractParameterValue subtypes
# These are wrappers around some standard Julia types and our parameter value types, that override the call operator
struct NothingParameterValue <: AbstractParameterValue end

struct ScalarParameterValue{T} <: AbstractParameterValue
    value::T
end

struct ArrayParameterValue{T,N} <: AbstractParameterValue
    value::Array{T,N}
end

struct TimePatternParameterValue{T} <: AbstractParameterValue
    value::TimePattern{T}
end

struct StandardTimeSeriesParameterValue{V} <: AbstractTimeSeriesParameterValue
    value::TimeSeries{V}
end

struct RepeatingTimeSeriesParameterValue{V} <: AbstractTimeSeriesParameterValue
    value::TimeSeries{V}
    span::Union{Period,Nothing}
    valsum::V
    len::Int64
end

struct MapParameterValue{K,V} <: AbstractParameterValue where {V<:AbstractParameterValue}
    value::Map{K,V}
end

TimeVaryingParameterValue = Union{AbstractTimeSeriesParameterValue,TimePatternParameterValue}

_OriginalCall = Tuple{Symbol,NamedTuple}

struct IdentityCall{C,T} <: Call
    original_call::C
    value::T
end

struct OperatorCall{T} <: Call where {T<:Function}
    operator::T
    args::Array{Any,1}
    OperatorCall(operator::T, args) where {T<:Function} = new{T}(operator, args)
end

struct ParameterValueCall{C,T} <: Call where {T<:AbstractParameterValue}
    original_call::C
    parameter_value::T
    kwargs::NamedTuple
end

mutable struct _IsLowestResolution
    ref::Array{Union{TimeSlice,Nothing},1}
    function _IsLowestResolution(t_arr::Array{TimeSlice,1})
        ref = [nothing]
        sizehint!(ref, length(t_arr))
        new(ref)
    end
end

mutable struct _IsHighestResolution
    ref::Array{Union{TimeSlice,Nothing},1}
    function _IsHighestResolution(t_arr::Array{TimeSlice,1})
        ref = [nothing]
        sizehint!(ref, length(t_arr))
        new(ref)
    end
end

struct _DateTimeRef
    ref::Ref{DateTime}
end
