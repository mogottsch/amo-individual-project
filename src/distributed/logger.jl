struct LoggerConfig
    prefix::String
end

function log(config::LoggerConfig, msg)
    return "[$(config.prefix)] $msg"
end

function createLogger(prefix::String)
    return LoggerConfig(prefix)
end
