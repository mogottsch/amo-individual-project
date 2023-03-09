import Statistics


include("config.jl")
include("logger.jl")
include("../admm.jl")


function startController(config::Config, state::State, data::Data)
    logger = createLogger("CONTROLLER")
    channel = state.mainChannel
    connected = state.connected

    localK = 0
    ϵ = config.ϵ
    ρ = config.ρ
    busses, lines = data.busses, data.lines

    δs, λ_δs = initVars(busses, lines)

    @info log(logger, "Controller started")

    startTime = nothing
    startTimeAfterFirstIteration = nothing

    clientUpdates = ClientUpdate[]

    while true
        clientUpdate = take!(channel)
        clientId = clientUpdate.id
        if localK == 0
            nConnected = length(connected)
            @info log(logger, "Client $clientId registered ($nConnected / $(config.N_CLIENTS))")
        else
            @debug log(logger, "Client $clientId answered")
        end

        if localK == 0
            if length(connected) == config.N_CLIENTS
                @info log(logger, "All clients connected")
                waitForUserConfirmation(logger)
                startTime = time()
                localK = startNextIteration(state, δs, λ_δs, logger)
            end
            continue
        end

        push!(clientUpdates, clientUpdate)

        if localK == 2 && startTimeAfterFirstIteration === nothing
            startTimeAfterFirstIteration = time()
        end


        if length(clientUpdates) == config.N_CLIENTS
            @debug log(logger, "All clients answered")

            δs, residuals, diffs_λ_δs, λ_δs, Ps, sum_objectives = processUpdates(clientUpdates, data, λ_δs, ρ)

            converged = checkConvergence(residuals, diffs_λ_δs, ρ, ϵ, logger, localK)

            clientUpdates = ClientUpdate[]

            if converged
                @info "Converged"
                @info "δs: $δs"
                @info "Ps: $Ps"
                @info "Objective: $sum_objectives"
                timeElapsed = time() - startTime
                timeElapsedAfterFirstIteration = time() - startTimeAfterFirstIteration
                @info "Time elapsed: $timeElapsed"
                @info "Time elapsed after first iteration: $timeElapsedAfterFirstIteration"
                return timeElapsed, sum_objectives
                break
            end

            localK = startNextIteration(state, δs, λ_δs, logger)
        end

    end
    @info log(logger, "Controller finished")
end

function processUpdates(
    clientUpdates::Vector{ClientUpdate},
    data::Data,
    λ_δs::Dict{Symbol,Dict{Symbol,Float64}},
    ρ::Float64
)
    busses, lines = data.busses, data.lines
    results, Ps, sum_objectives = convertResults(clientUpdates)

    aggregated_results = aggregate_results(results)
    residuals, diffs_λ_δs, new_λ_δs = update_dual_variables(busses, lines, aggregated_results, results, λ_δs, ρ)


    return aggregated_results, residuals, diffs_λ_δs, new_λ_δs, Ps, sum_objectives
end

function checkConvergence(
    residuals::Array{Float64,1},
    diffs_λ_δs::Array{Float64,1},
    ρ::Float64,
    ϵ::Float64,
    logger::LoggerConfig,
    k::Int
)::Bool
    r, s = get_convergence(residuals, diffs_λ_δs, ρ)
    primal_convergence = r < ϵ
    dual_convergence = s < ϵ

    @info log(logger, "k=$k, Primal convergence: $r, Dual convergence: $s")

    return primal_convergence && dual_convergence
end

function convertResults(
    clientUpdates::Vector{ClientUpdate}
)::Tuple{Dict{Symbol,Dict{Symbol,Float64}},Dict{Symbol,Float64},Float64}
    results = Dict{Symbol,Dict{Symbol,Float64}}()
    Ps = Dict{Symbol,Float64}()
    sum_objectives = 0

    for clientUpdate in clientUpdates
        id = Symbol(clientUpdate.id)
        δs = clientUpdate.δs
        results[id] = δs
        if clientUpdate.P !== nothing
            Ps[id] = clientUpdate.P
        end
        sum_objectives += clientUpdate.objective
    end
    return results, Ps, sum_objectives
end

function waitForUserConfirmation(logger::LoggerConfig)
    @info log(logger, "Press enter to start")
    readline()
end

function startNextIteration(
    state::State,
    δs::Dict{Symbol,Float64},
    λ_δs::Dict{Symbol,Dict{Symbol,Float64}},
    logger::LoggerConfig)::Int
    lock(state.mutex) do
        state.k = state.k + 1
    end

    @debug log(logger, "Starting iteration $(state.k)")
    newValues = (δs, λ_δs)
    @debug log(logger, "Notifying clients")
    nWoken = nothing
    lock(state.nextIteration) do
        nWoken = notify(state.nextIteration, newValues)
    end

    @debug log(logger, "Woke up $nWoken clients")
    return state.k
end

