using WebSockets
import HTTP
import Statistics

const LOCALIP = "0.0.0.0" # listen on all interfaces
const PORT = 1234

include("config.jl")

function startController(config::Config, state::State)
    logger = createLogger("CONTROLLER")
    channel = state.mainChannel
    connected = state.connected

    localK = 0
    currentMean = 0.0
    ϵ = 0.1

    @info log(logger, "Controller started")

    recValues = Float64[]

    while true
        clientUpdate = take!(channel)
        @info log(logger, "Got message: $clientUpdate")

        if localK == 0
            if length(connected) == config.N_CLIENTS
                @info log(logger, "All clients connected")
                waitForUserConfirmation(logger)
                localK = startNextIteration(state, currentMean, logger)
            end
            continue
        end

        push!(recValues, clientUpdate.value)

        if length(recValues) == config.N_CLIENTS
            @info log(logger, "All clients answered")

            newMean = Statistics.mean(recValues)
            std = Statistics.std(recValues)
            recValues = Float64[]

            @info log(logger, "Std: $std")
            if std < ϵ
                @info "Converged"
                break
            end

            currentMean = newMean
            @info log(logger, "New mean: $currentMean")

            localK = startNextIteration(state, currentMean, logger)
        end

    end
    @info log(logger, "Controller finished")
end

function waitForUserConfirmation(logger::LoggerConfig)
    @info log(logger, "Press enter to start")
    readline()
end

function startNextIteration(state::State, mean::Float64, logger::LoggerConfig)::Int
    lock(state.mutex) do
        state.k = state.k + 1
    end

    @info log(logger, "Notifying clients")
    nWoken = nothing
    lock(state.nextIteration) do
        nWoken = notify(state.nextIteration, mean)
    end

    @info log(logger, "Woke up $nWoken clients")
    return state.k
end

