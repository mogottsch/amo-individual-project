import WebSockets

include("logger.jl")

realistic_latency_ms = 28
function readWs(ws::WebSockets.WebSocket, logger::LoggerConfig)::Tuple{String,Bool}
    data, stillopen = WebSockets.readguarded(ws)
    if !stillopen
        @warn log(logger, "Connection closed by peer")
        return "", false
    end
    return String(data), true
end

function writeWs(ws::WebSockets.WebSocket, data::String, logger::LoggerConfig)::Bool
    stillopen = WebSockets.writeguarded(ws, data)
    if !stillopen
        @warn log(logger, "Connection closed by peer")
        return false
    end
    return true
end
