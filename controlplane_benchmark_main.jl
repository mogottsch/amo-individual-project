import Pkg;
Pkg.activate(".");
Pkg.instantiate();

include("./src/distributed/controlplane.jl")
import CSV
using DataFrames

function main()
    @info "Running with $(Threads.nthreads()) threads"
    ieee_files = filter(contains("ieee"), readdir("./data"; join=true))
    # ieee_files = ["./data/ieee14cdf.txt"]

    results_df = DataFrame(
        :file => String[],
        :method => String[],
        :elapsed => Float64[],
        :objective => Float64[],
        :has_converged => Bool[],
    )
    method = "distributed_latency"
    has_converged = true # we set no limit on the number of iterations

    for ieee_file in ieee_files
        r = startControlPlane(ieee_file)
        elapsed, objective = r
        push!(results_df, (ieee_file, method, elapsed, objective, has_converged))
    end

    CSV.write("./results/distributed_latency_results.csv", results_df)
end


main()

