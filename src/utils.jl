using DataFrames
include("common.jl")

function create_bus_df(busses::Dict{Symbol,Bus})::DataFrame
    df = DataFrame(
        :id => [],
        :cost => [],
        :P_min => [],
        :P_max => [],
        :load => [],
        :incoming => [],
        :outgoing => [],
    )
    for (id, bus) in busses
        push!(df, Dict(
            :id => id,
            :cost => bus.cost,
            :P_min => bus.P_min,
            :P_max => bus.P_max,
            :load => bus.load,
            :incoming => bus.incoming,
            :outgoing => bus.outgoing,
        ))
    end
    return df
end

function create_lines_df(lines::Dict{Symbol,Line})::DataFrame
    df = DataFrame(
        :id => [],
        :from => [],
        :to => [],
        :capacity => [],
    )
    for (id, line) in lines
        push!(df, Dict(
            :id => id,
            :from => line.from,
            :to => line.to,
            :capacity => line.capacity,
        ))
    end
    return df
end