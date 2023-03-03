
struct Config
    N_CLIENTS::Int
end


struct ClientUpdate
    id::String
    value::Float64
end

mutable struct State
    k::Int
    connected::Set{String}
    mainChannel::Channel{ClientUpdate}
    nextIteration::Threads.Condition
    mutex::ReentrantLock
end
