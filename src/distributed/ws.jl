import WebSockets

include("logger.jl")

function readWs(ws::WebSockets.WebSocket, logger::LoggerConfig)::Tuple{String,Bool}
    data, stillopen = WebSockets.readguarded(ws)
    if !stillopen
        @warn log(logger, "Connection closed by peer")
        return "", false
    end
    return String(data), true
end

realistic_latency_ms = 28
function writeWs(ws::WebSockets.WebSocket, data::String, logger::LoggerConfig)::Bool
    # sleep(realistic_latency_ms / 1000)
    stillopen = WebSockets.writeguarded(ws, data)
    if !stillopen
        @warn log(logger, "Connection closed by peer")
        return false
    end
    return true
end
