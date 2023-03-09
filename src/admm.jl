using JuMP
include("./common.jl")

struct AdmmConfig
    ρ::Float64
    use_multithreading::Bool
    silent::Bool
end

function create_admm_config(config_dict::Dict)::AdmmConfig
    c = copy(config_dict)
    parsed = Dict()
    expected_keys = [:ρ, :use_multithreading, :silent]
    for key in expected_keys
        if !haskey(c, key)
            error("Missing key $key in config")
        end
        parsed[key] = c[key]
        delete!(c, key)
    end

    if length(c) > 0
        error("Unexpected keys in config: $(keys(c))")
    end

    return AdmmConfig(parsed[:ρ], parsed[:use_multithreading], parsed[:silent])
end

function solve_with_admm(busses::Dict{Symbol,Bus}, lines::Dict{Symbol,Line}, config::AdmmConfig)
    ρ = config.ρ
    ϵ = 0.0001
    Ps = Dict()

    δs, λ_δs = initVars(busses, lines)
    has_converged = false
    objective = Inf

    # ρ_orig = ρ

    for i in 1:10000

        # --- ADMM update steps start ---
        ## update rule for local variables
        if config.use_multithreading
            results, Ps, objective = solve_subproblems_multithreaded(busses, lines, δs, λ_δs, ρ)
        else
            results, Ps, objective = solve_subproblems(busses, lines, δs, λ_δs, ρ)
        end

        ## update rule for global variables
        aggregated_results = aggregate_results(results)

        ## update rule for dual variables
        residuals, diffs_λ_δs, new_λ_δs = update_dual_variables(busses, lines, aggregated_results, results, λ_δs, ρ)
        # --- ADMM update steps end ---

        r, s = get_convergence(residuals, diffs_λ_δs, ρ)
        primal_convergence = r < ϵ
        dual_convergence = s < ϵ

        λ_δs = new_λ_δs
        δs = aggregated_results

        if !config.silent
            print_iteration(i, r, s)
        end

        # ρ = update_penalty_parameter(r, s, ρ)
        # ρ = ρ_orig / i

        if primal_convergence && dual_convergence
            if !config.silent
                println("Converged")
            end
            has_converged = true
            break
        end
    end

    if !has_converged
        if !config.silent
            @warn("Did not converge")
        end
    end

    P_results = Dict{Symbol,Float64}()
    for bus_id in keys(busses)
        P_results[bus_id] = Ps[bus_id]
    end

    return Ps, δs, objective, has_converged
end

# function update_penalty_parameter(r::Float64, s::Float64, ρ::Float64)::Float64
#     total = r + s

# end

function solve_bus_problem(
    bus::Bus,
    δs::Dict{Symbol,Float64},
    λ_δs::Dict{Symbol,Float64},
    ρ::Float64
)
    m = create_model()

    @variable(m, bus.P_min <= P <= bus.P_max)
    @variable(m, δ[line_id in union(bus.incoming, bus.outgoing)])

    @constraint(m,
        bus.load ==
        P +
        sum(δ[line_id] for line_id in bus.incoming) -
        sum(δ[line_id] for line_id in bus.outgoing)
    )

    @objective(m, Min,
        bus.cost * P +
        sum(λ_δs[line_id] * δ[line_id] for line_id in union(bus.incoming, bus.outgoing)) +
        ρ / 2 * sum((δ[line_id] - δs[line_id])^2 for line_id in union(bus.incoming, bus.outgoing))
    )

    JuMP.optimize!(m)

    δ_results = Dict{Symbol,Float64}()
    for line_id in union(bus.incoming, bus.outgoing)
        δ_results[line_id] = JuMP.value.(δ[line_id])
    end
    return Dict(
        :P => JuMP.value.(P),
        :δ => δ_results,
        :objective => JuMP.objective_value(m)
    )
end


function solve_line_problem(
    line::Line,
    δs::Dict{Symbol,Float64},
    λ_δs::Dict{Symbol,Float64},
    ρ::Float64
)::Dict{Symbol,Any}
    m = create_model()

    @variable(m, -line.capacity <= δ <= line.capacity)

    @objective(m, Min, λ_δs[line.id] * δ + ρ / 2 * (δ - δs[line.id])^2)

    JuMP.optimize!(m)
    return Dict(
        :δ => Dict(line.id => JuMP.value.(δ)),
        :objective => JuMP.objective_value(m)
    )
end

function initVars(
    busses::Dict{Symbol,Bus},
    lines::Dict{Symbol,Line}
)::Tuple{Dict{Symbol,Float64},Dict{Symbol,Dict{Symbol,Float64}}}
    δs = Dict()
    for line_id in keys(lines)
        δs[line_id] = 0
    end
    λ_δs = Dict()
    for line_id in keys(lines)
        λ_δs[line_id] = Dict(line_id => 0)
    end
    for bus_id in keys(busses)
        λ_δs[bus_id] = Dict()
        for line_id in union(busses[bus_id].incoming, busses[bus_id].outgoing)
            λ_δs[bus_id][line_id] = 0
        end
    end

    return δs, λ_δs
end



function solve_subproblems(
    busses::Dict{Symbol,Bus},
    lines::Dict{Symbol,Line},
    δs::Dict{Symbol,Float64},
    λ_δs::Dict{Symbol,Dict{Symbol,Float64}},
    ρ::Float64
)::Tuple{Dict{Symbol,Dict{Symbol,Float64}},Dict{Symbol,Float64},Float64}
    results = Dict()
    Ps = Dict()
    sum_objectives = 0
    for (bus_id, bus) in busses
        bus_result = solve_bus_problem(bus, δs, λ_δs[bus_id], ρ)
        results[bus_id] = bus_result[:δ]
        Ps[bus_id] = bus_result[:P]
        sum_objectives += bus_result[:objective]
    end

    for (line_id, line) in lines
        line_results = solve_line_problem(line, δs, λ_δs[line_id], ρ)
        results[line_id] = line_results[:δ]
        sum_objectives += line_results[:objective]
    end
    return results, Ps, sum_objectives
end


function solve_subproblems_multithreaded(
    busses::Dict{Symbol,Bus},
    lines::Dict{Symbol,Line},
    δs::Dict{Symbol,Float64},
    λ_δs::Dict{Symbol,Dict{Symbol,Float64}},
    ρ::Float64
)::Tuple{Dict{Symbol,Dict{Symbol,Float64}},Dict{Symbol,Float64},Float64}

    if Threads.nthreads() == 1
        error("Expected more than one thread")
    end

    results = Dict()
    Ps = Dict()
    sum_objectives = 0
    lk = ReentrantLock()

    bus_tasks = collect(keys(busses))
    line_tasks = collect(keys(lines))

    all_tasks = vcat(bus_tasks, line_tasks)

    Threads.@threads for id in all_tasks
        type = string(id)[1] == 'B' ? "bus" : "line"
        if type == "bus"
            bus_id = id
            bus = busses[bus_id]
            bus_result = solve_bus_problem(bus, δs, λ_δs[bus_id], ρ)
            lock(lk) do
                results[bus_id] = bus_result[:δ]
                Ps[bus_id] = bus_result[:P]
                sum_objectives += bus_result[:objective]
            end
        else
            line_id = id
            line = lines[line_id]
            line_results = solve_line_problem(line, δs, λ_δs[line_id], ρ)
            lock(lk) do
                results[line_id] = line_results[:δ]
                sum_objectives += line_results[:objective]
            end
        end

    end

    return results, Ps, sum_objectives
end

function aggregate_results(results::Dict{Symbol,Dict{Symbol,Float64}})::Dict{Symbol,Float64}
    pooled_results = Dict()
    for result in values(results)
        for (key, value) in result
            if !haskey(pooled_results, key)
                pooled_results[key] = []
            end
            push!(pooled_results[key], value)
        end
    end
    agg_results = Dict()
    for (key, value) in pooled_results
        agg_results[key] = sum(value) / length(value)
    end

    return agg_results
end


function update_dual_variables(
    busses::Dict{Symbol,Bus},
    lines::Dict{Symbol,Line},
    agg_results::Dict{Symbol,Float64},
    results::Dict{Symbol,Dict{Symbol,Float64}},
    λ_δs::Dict{Symbol,Dict{Symbol,Float64}},
    ρ::Float64
)::Tuple{Array{Float64,1},Array{Float64,1},Dict{Symbol,Dict{Symbol,Float64}}}
    residuals = []
    diffs_λ_δs = []
    new_λ_δs = Dict()

    for line_id in keys(lines)
        local_results = results[line_id]
        residual = local_results[line_id] - agg_results[line_id]

        push!(residuals, residual)
        new_λ_δs[line_id] = Dict(line_id => λ_δs[line_id][line_id] + ρ * residual)
        push!(diffs_λ_δs, new_λ_δs[line_id][line_id] - λ_δs[line_id][line_id])
    end

    for (bus_id, bus) in busses
        local_results = results[bus_id]
        new_λ_δ = Dict()
        for line_id in union(bus.incoming, bus.outgoing)
            residual = local_results[line_id] - agg_results[line_id]

            push!(residuals, residual)
            new_λ_δ[line_id] = λ_δs[bus_id][line_id] + ρ * residual
            push!(diffs_λ_δs, new_λ_δ[line_id] - λ_δs[bus_id][line_id])
        end
        new_λ_δs[bus_id] = new_λ_δ
    end

    return residuals, diffs_λ_δs, new_λ_δs
end

function get_convergence(
    residuals::Array{Float64,1},
    diffs_λ_δs::Array{Float64,1},
    ρ::Float64,
)::Tuple{Float64,Float64}
    s = sum((diffs_λ_δs) .^ 2) * ρ^2 * length(diffs_λ_δs)
    r = sum((residuals) .^ 2)

    return r, s
end

function print_iteration(i::Int64, r::Float64, s::Float64)
    print(lpad(i, 3, " "))
    print(" ")
    print(lpad(r, 10, " "))
    print(" ")
    println(lpad(s, 10, " "))
end
