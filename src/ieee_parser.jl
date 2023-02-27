include("common.jl")


POWER_GENERATION_SCALING_FACTOR = 1.5
LINE_CAPACITY = 1000


TITLE_ROW_INDEX = 1
BUS_SECTION_START = "BUS DATA FOLLOWS"
BRANCH_SECTION_START = "BRANCH DATA FOLLOWS"
LOSS_ZONE_SECTION_START = "LOSS ZONES FOLLOWS"
INTERCHANGE_SECTION_START = "INTERCHANGE DATA FOLLOWS"
TIE_LINE_SECTION_START = "TIE LINES FOLLOWS"

END_SECTION_PREFIX = "-9"

function read_IEEE_common_data_format(filepath::String)
    filelines = readlines(filepath)

    (
        bus_section,
        branch_section,
        # loss_zone_section,
        # interchange_section,
        # tie_line_section
    ) = get_sections(filelines)

    busses = parse_bus_section(bus_section)
    lines = parse_branch_section!(branch_section, busses)

    return busses, lines
end

function get_sections(
    filelines::Vector{String}
)::Tuple{Vector{String},Vector{String}}
    bus_section = get_section(filelines, BUS_SECTION_START)
    branch_section = get_section(filelines, BRANCH_SECTION_START)
    # loss_zone_section = get_section(filelines, LOSS_ZONE_SECTION_START)
    # interchange_section = get_section(filelines, INTERCHANGE_SECTION_START)
    # tie_line_section = get_section(filelines, TIE_LINE_SECTION_START)

    return (
        bus_section,
        branch_section,
        # loss_zone_section,
        # interchange_section,
        # tie_line_section
    )
end


HEADER_OFFSET = FOOTER_OFFSET = 1
function get_section(
    filelines::Vector{String},
    section_start::String
)::Vector{String}
    contains_section_start = x -> occursin(section_start, x)
    contains_section_end = x -> startswith(x, END_SECTION_PREFIX)

    section_start_index = findfirst(contains_section_start, filelines)
    if section_start_index === nothing
        error("Start of section $section_start not found")
    end

    section_end_index = findnext(contains_section_end, filelines, section_start_index)
    if section_end_index === nothing
        error("End of section $section_start not found")
    end

    return filelines[section_start_index+HEADER_OFFSET:section_end_index-FOOTER_OFFSET]
end


DEFAULT_REINFORCMENT_COST = 100.0
BUS_NUMBER_COLUMNS = 1:4
BUS_VOLTAGE_COLUMNS = 28:33
BUS_LOAD_COLUMNS = 41:49
BUS_GENERATION_COLUMNS = 60:67
function parse_bus_section(bus_section::Vector{String})::Dict{Symbol,Bus}
    busses = Dict()

    for fileline in bus_section
        bus = parse_bus_section_fileline(fileline)
        busses[bus.id] = bus
    end

    return busses
end

function parse_bus_section_fileline(fileline::String)
    bus_number = parse(Int, fileline[BUS_NUMBER_COLUMNS])
    bus_id = Symbol(:B, bus_number)
    bus_load = abs(parse(Float64, fileline[BUS_LOAD_COLUMNS]))
    bus_generation = abs(parse(Float64, fileline[BUS_GENERATION_COLUMNS])) * POWER_GENERATION_SCALING_FACTOR

    bus = Bus(
        bus_id,
        35.0,
        0,
        bus_generation,
        bus_load,
        Set(),
        Set()
    )

    return bus
end

function parse_branch_section!(
    branch_section::Vector{String},
    busses::Dict{Symbol,Bus}
)::Dict{Symbol,Line}
    lines = Dict()

    for fileline in branch_section
        line = parse_branch_section_fileline!(fileline, busses)
        lines[line.id] = line
    end

    return lines
end

DEFAULT_LINE_CAPACITY = 100.0

BRANCH_FROM_BUS_COLUMNS = 1:4
BRANCH_TO_BUS_COLUMNS = 6:9
BRANCH_RESISTANCE_COLUMNS = 20:29
BRANCH_REACTANCE_COLUMNS = 30:40

function parse_branch_section_fileline!(
    fileline::String,
    busses::Dict{Symbol,Bus}
)
    from_bus_number = parse(Int, fileline[BRANCH_FROM_BUS_COLUMNS])
    to_bus_number = parse(Int, fileline[BRANCH_TO_BUS_COLUMNS])
    from_bus_id = Symbol(:B, from_bus_number)
    to_bus_id = Symbol(:B, to_bus_number)

    # resistance = parse(Float64, fileline[BRANCH_RESISTANCE_COLUMNS])
    # reactance = parse(Float64, fileline[BRANCH_REACTANCE_COLUMNS])
    # susceptance = calculate_susceptance(reactance, resistance)

    line_id = Symbol(:LF, from_bus_number, :T, to_bus_number)
    line = Line(
        line_id,
        from_bus_id,
        to_bus_id,
        LINE_CAPACITY,
    )

    push!(busses[from_bus_id].outgoing, line_id)
    push!(busses[to_bus_id].incoming, line_id)

    return line
end

function calculate_susceptance(reactance::Float64, resistance::Float64)::Float64
    impedance = resistance + reactance * im
    admittance = 1 / impedance
    susceptance = imag(admittance)
    return susceptance
end