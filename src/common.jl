import JuMP
import Gurobi

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

struct Line
    id::Symbol
    from::Symbol
    to::Symbol
    capacity::Float64
end


function create_model()::JuMP.Model
    m = JuMP.Model(() -> Gurobi.Optimizer(GRB_ENV))
    set_optimizer_attribute(m, "OutputFlag", 0)
    return m
end