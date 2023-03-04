import Pkg;
Pkg.activate(".");
Pkg.instantiate();


include("./src/distributed/client.jl")

function main(args)
    if length(args) != 1
        println("Usage: julia client.jl <id>")
        return
    end
    startClient(args[1])

end

main(ARGS)
