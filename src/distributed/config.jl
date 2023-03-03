include("../common.jl")

struct Config
    N_CLIENTS::Int
    ϵ::Float64 # convergence criterion
    ρ::Float64 # step size / admm parameter
end

struct Data
    busses::Dict{Symbol,Bus}
    lines::Dict{Symbol,Line}
    clients::Set{String}
end


function createData(busses::Dict{Symbol,Bus}, lines::Dict{Symbol,Line})::Data
    clients = Set{String}()
    for (id, bus) in busses
        push!(clients, string(id))
    end
    for (id, line) in lines
        push!(clients, string(id))
    end
    return Data(busses, lines, clients)
end


struct ClientUpdate
    id::String
    type::Symbol
    δs::Dict{Symbol,Float64}
    P::Union{Nothing,Float64}
    objective::Float64
end



mutable struct State
    k::Int
    connected::Set{String}
    mainChannel::Channel{ClientUpdate}
    nextIteration::Threads.Condition
    mutex::ReentrantLock
end

function initState(nClients::Int)::State
    mutex = ReentrantLock()
    mainChannel = Channel{ClientUpdate}(nClients)
    nextIteration = Threads.Condition()
    return State(0, Set{String}(), mainChannel, nextIteration, mutex)
end
