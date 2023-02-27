include("common.jl")
import XLSX
import Dates
using DataFrames
import Dates


BUS_SHEET_NAME = "Bus"
BRANCH_SHEET_NAME = "Branch"
GENERATOR_SHEET_NAME = "Gen"
LOAD_SHEET_NAME = "hourly_BusLoadP (MW)"

function read_rwth_data_format(filepath::String)
    busses = parse_busses(filepath)
    lines = parse_lines!(filepath, busses)
    parse_generators!(filepath, busses)

    parse_loads!(filepath, busses)


    return busses, lines
end


function read_sheet(filepath::String, sheet_name::String)::DataFrame
    df = DataFrame(XLSX.readtable(filepath, sheet_name))
    return df
end

BUS_ID_COL = Symbol("Number")
function parse_busses(filepath::String)::Dict{Symbol,Bus}
    df = read_sheet(filepath, BUS_SHEET_NAME)
    busses = Dict()
    for row in eachrow(df)
        bus = parse_bus(row)
        busses[bus.id] = bus
    end
    return busses
end

function parse_bus(row::DataFrameRow)::Bus
    bus_id = Symbol(:B, row[BUS_ID_COL])
    bus = Bus(
        bus_id,
        1,
        0,
        0,
        0,
        Set(),
        Set(),
    )
    return bus
end

LINE_ID_COL = Symbol("BranchID")
LINE_FROM_COL = Symbol("From Bus No.")
LINE_TO_COL = Symbol("To Bus No.")
LINE_CAPACITY_COL = Symbol("Rating [MW]")

function parse_lines!(filepath::String, busses::Dict{Symbol,Bus})::Dict{Symbol,Line}
    df = read_sheet(filepath, BRANCH_SHEET_NAME)
    lines = Dict()
    for row in eachrow(df)
        line = parse_line(row)
        lines[line.id] = line

        push!(busses[line.from].outgoing, line.id)
        push!(busses[line.to].incoming, line.id)
    end
    return lines
end

function parse_line(row::DataFrameRow)::Line
    from_bus = Symbol(:B, row[LINE_FROM_COL])
    to_bus = Symbol(:B, row[LINE_TO_COL])
    line_id = Symbol(:LF, from_bus, :T, to_bus)
    line = Line(
        line_id,
        from_bus,
        to_bus,
        row[LINE_CAPACITY_COL],
    )
    return line
end


GENERATOR_ID_COL = Symbol("Generator Number")
GENERATOR_BUS_ID_COL = Symbol("On Bus No.")
GENERATOR_MAX_CAPACITY_COL = Symbol("Pmax [MW]")
GENERATOR_MIN_CAPACITY_COL = Symbol("Pmin [MW]")
GENERATOR_COSTS_COL = Symbol("Costs [€/MW]")

function parse_generators!(filepath::String, busses::Dict{Symbol,Bus})
    df = read_sheet(filepath, GENERATOR_SHEET_NAME)
    for row in eachrow(df)
        bus_id = Symbol(:B, row[GENERATOR_BUS_ID_COL])
        bus = busses[bus_id]
        newCosts = row[GENERATOR_COSTS_COL]
        if bus.P_max != 0 && (bus.cost != row[GENERATOR_COSTS_COL])
            newCosts = (bus.cost + row[GENERATOR_COSTS_COL]) / 2
        end
        newBus = Bus(
            bus.id,
            max(newCosts, 1),
            0,
            row[GENERATOR_MAX_CAPACITY_COL] + bus.P_max,
            bus.load,
            bus.incoming,
            bus.outgoing,
        )

        busses[bus_id] = newBus
    end
end

LOAD_HOUR_COL = Symbol("Hour/Bus No.")
function parse_loads!(filepath::String, busses)
    df = read_sheet(filepath, LOAD_SHEET_NAME)
    df[!, :] = convert.(Float64, df[!, :])

    select!(df, Not(LOAD_HOUR_COL))

    colnames = names(df)
    new_colnames = [Symbol("B", i) for i in colnames]

    rename!(df, new_colnames)

    avg_load = mean.(eachcol(loads))
    for (i, load) in enumerate(avg_load)
        bus_id = Symbol("B", i)
        bus = busses[bus_id]
        newBus = Bus(
            bus.id,
            bus.cost,
            bus.P_min,
            bus.P_max,
            load,
            bus.incoming,
            bus.outgoing,
        )
        busses[bus_id] = newBus
    end
end

function parse_date(hour::Float64)::Dates.DateTime
    datetime = Dates.DateTime(2023, 1, 1, 1)
    return datetime + Dates.Hour(hour)
end