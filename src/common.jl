import JuMP
import Gurobi
import JSON

if !(@isdefined GRB_ENV)
    GRB_ENV = Gurobi.Env()
end

struct Bus
    id::Symbol
    cost::Float64
    P_min::Float64
    P_max::Float64
    load::Float64
    incoming::Set{Symbol}
    outgoing::Set{Symbol}
end

function busToJSON(bus::Bus)::Dict{String,Any}
    return Dict(
        "id" => string(bus.id),
        "cost" => bus.cost,
        "P_min" => bus.P_min,
        "P_max" => bus.P_max,
        "load" => bus.load,
        "incoming" => [string(id) for id in bus.incoming],
        "outgoing" => [string(id) for id in bus.outgoing]
    )
end

function busFromJSON(bus::Dict)::Bus
    return Bus(
        Symbol(bus["id"]),
        bus["cost"],
        bus["P_min"],
        bus["P_max"],
        bus["load"],
        Set{Symbol}([Symbol(id) for id in bus["incoming"]]),
        Set{Symbol}([Symbol(id) for id in bus["outgoing"]])
    )
end

struct Line
    id::Symbol
    from::Symbol
    to::Symbol
    capacity::Float64
end

function lineToJSON(line::Line)::Dict{String,Any}
    return Dict(
        "id" => string(line.id),
        "from" => string(line.from),
        "to" => string(line.to),
        "capacity" => line.capacity
    )
end

function lineFromJSON(line::Dict)::Line
    return Line(
        Symbol(line["id"]),
        Symbol(line["from"]),
        Symbol(line["to"]),
        line["capacity"]
    )
end


function toJSON(U::Union{Bus,Line})::Dict{String,Any}
    if U isa Bus
        return busToJSON(U)
    elseif U isa Line
        return lineToJSON(U)
    else
        error("Unknown type")
    end
end


function create_model()::JuMP.Model
    m = JuMP.Model(() -> Gurobi.Optimizer(GRB_ENV))
    set_optimizer_attribute(m, "OutputFlag", 0)
    return m
end
