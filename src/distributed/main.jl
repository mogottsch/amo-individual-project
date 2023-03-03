import Pkg;
Pkg.activate(".");
Pkg.instantiate();


include("server.jl")

startFor("data/ieee14cdf.txt")

