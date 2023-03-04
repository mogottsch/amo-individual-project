using JuMP

include("./common.jl")

function solve_with_lp(busses::Dict{Symbol,Bus}, lines::Dict{Symbol,Line})
    m = create_model()

    @variable(m, -lines[line_id].capacity <= δ[line_id in keys(lines)] <= lines[line_id].capacity)
    @variable(m, busses[bus_id].P_min <= P[bus_id in keys(busses)] <= busses[bus_id].P_max)

    for bus_id in keys(busses)
        bus = busses[bus_id]
        @constraint(m, bus.load == P[bus_id] + sum(δ[line_id] for line_id in bus.incoming) - sum(δ[line_id] for line_id in bus.outgoing))
    end

    @objective(m, Min, sum(busses[bus_id].cost * P[bus_id] for bus_id in keys(busses)))

    JuMP.optimize!(m)

    δ_results = Dict{Symbol,Float64}()
    for line_id in keys(lines)
        δ_results[line_id] = JuMP.value.(δ[line_id])
    end
    P_results = Dict{Symbol,Float64}()
    for bus_id in keys(busses)
        P_results[bus_id] = JuMP.value.(P[bus_id])
    end

    objective = JuMP.objective_value(m)
    return P_results, δ_results, objective
end