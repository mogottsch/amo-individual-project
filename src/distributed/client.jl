import Pkg;
Pkg.activate(".");
Pkg.instantiate();

import WebSockets

include("ws.jl")
include("logger.jl")
include("utils.jl")
include("../admm.jl")
include("../common.jl")

ρ = 0.1

function clientRoutine(ws::WebSockets.WebSocket, id::String)
    logger = createLogger("CLIENT - $id")

    @info log(logger, "Starting client routine")
    i = 0
    type = checkIsBus(id) ? :bus : :line

    object = nothing

    message = "id:$id"
    stillopen = writeWs(ws, message, logger)
    if !stillopen
        return
    end

    message, stillopen = readWs(ws, logger)
    if !stillopen
        return
    end

    parsed = nothing
    try
        parsed = JSON.parse(message)
    catch e
        @error log(logger, "Could not parse value") exception = (e, catch_backtrace())
        return
    end
    if type == :bus
        object = busFromJSON(parsed)
    else
        object = lineFromJSON(parsed)
    end
    @info log(logger, "$type initialized : $object")

    while isopen(ws)
        @info log(logger, "Waiting for message")
        message, stillopen = readWs(ws, logger)
        if !stillopen
            break
        end

        @info log(logger, "Received message: $message")
        λ_δs, k, δs = parseServerUpdate(message)
        @info log(logger, "Current iteration: $k")

        λ_δs = Dict{Symbol,Float64}(Symbol(k) => v for (k, v) in λ_δs)
        δs = Dict{Symbol,Float64}(Symbol(k) => v for (k, v) in δs)

        @info log(logger, "Solving problem")
        results = nothing
        if type == :bus
            results = solve_bus_problem(object, δs, λ_δs, ρ)
        else
            results = solve_line_problem(object, δs, λ_δs, ρ)
        end
        @info log(logger, "Solved problem: $results")

        results[:deltas] = results[:δ]
        delete!(results, :δ)

        resultsEncoded = JSON.json(results)

        stillopen = writeWs(ws, resultsEncoded, logger)
        @info log(logger, "Sent message to server")
        if !stillopen
            break
        end

    end
end

function parseServerUpdate(message::String)
    parsed = JSON.parse(message)
    λ_δs = parsed["lambda_deltas"]
    k = parsed["k"]
    δs = parsed["deltas"]

    return λ_δs, k, δs
end

function main(args)
    if length(args) != 1
        println("Usage: julia client.jl <id>")
        return
    end

    function callRoutine(ws::WebSockets.WebSocket)
        try
            clientRoutine(ws, args[1])
        catch e
            @error exception = (e, catch_backtrace()) # captures full stacktrace
        end
    end

    wsuri = "ws://127.0.0.1:1234"
    try
        res = WebSockets.open(callRoutine, wsuri)
    catch e
        @error exception = (e, catch_backtrace())
    end
end

main(ARGS)
