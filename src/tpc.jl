export load_tpc, load_tpc!

# TPC associated regular expressions (precompiled)
const _FIND_BODY_REGEX = Regex("(BODY\\w{1,}\\D{1,}=)")
const _FIND_DATA_REGEX = Regex("=\\D{1,}\\(([^()]*)\\)|(=\\D{1,}([0-9]*\\.?[0-9]*))")
const _FIND_BODY_INDEX = Regex("(?<=BODY)(.*?)(?=_)")
const _FIND_PROP_NAME_REGEX = Regex("(?<=\\d_)(.*?)(?==)")

"""
    PlanetaryConstantsDict{T}

Store TPC associated constants by NAIF ID.
"""
struct PlanetaryConstantsDict{T}
    data::Dict{Int, Dict{Symbol, Vector{T}}}
end

PlanetaryConstantsDict{T}() where T = PlanetaryConstantsDict{T}(Dict{Int, Dict{Symbol, Vector{T}}}())

Base.length(c::PlanetaryConstantsDict{T}) where T = length(c.data)
Base.keys(c::PlanetaryConstantsDict{T}) where T = keys(c.data)
Base.values(c::PlanetaryConstantsDict{T}) where T = values(c.data)
Base.eltype(::PlanetaryConstantsDict{T}) where T = T
Base.getindex(c::PlanetaryConstantsDict{T}, key) where T = getindex(c.data, key)

function Base.show(io::IO, cache::PlanetaryConstantsDict{T}) where T
    println(io, "ConstantsDict{$T} with $(length(cache.data)) entries:")
    for (idx, props) in cache.data 
        propstr = join([String(p) for p in keys(props)], ", ")
        println(io, "$idx => ($(propstr))")
    end
end

"""
    load_tpc!(cache::ConstantsDict{T}, file::String) where T

Load TPC file in the `cache` dictionary. 
"""
function load_tpc!(cache::PlanetaryConstantsDict{T}, file::String) where T

    @info "Loading constants from $file"
    # read document
    lines = readlines(file)
    # pre-allocate data for processing 
    saved = Vector{String}(undef, length(lines))

    save = false
    last_saved_index = 0
    # load and strip lines (remove tabs and spaces)
    # extract lines which are within `\begindata` and `\begintext`
    for line in lines
        line = strip(line)
        if line == "\\begindata"
            save = true 
            continue
        elseif  line == "\\begintext"
            save = false
            continue
        end
        if save 
            if line == ""
                continue
            end
            @inbounds saved[last_saved_index+1] = line
            last_saved_index += 1
        end
    end
    @inbounds resolved_lines = @view saved[1:last_saved_index]
    resolved_lines = join(resolved_lines, " ")

    # extract lines which actually have data using the `BODY**** =` pattern
    # this vector contains a list of `BODY******* =` elements
    name_idx = findall(_FIND_BODY_REGEX, resolved_lines)
    # row data are extracted as between square brackets, the `=` 
    # before the brackets is kept
    data_idx = findall(_FIND_DATA_REGEX, resolved_lines)

     # data are mapped to a dictionary
    @inbounds for i in eachindex(name_idx)
        if length(name_idx[i]) > 0
            # extract full name of the entry
            raw_name = resolved_lines[name_idx[i]]
            # parse naif id 
            naif = parse(Int, match(_FIND_BODY_INDEX, raw_name).match)
            # parse property name 
            prop = Symbol(lowercase(strip(match(_FIND_PROP_NAME_REGEX, raw_name).match)))
            # parse data
            raw_data = split(replace(resolved_lines[data_idx[i]], "D" => "E"))
            if raw_data[2] == "("
                # data is a vector
                mergewith!(
                    merge!, cache.data, 
                    Dict(
                        naif => Dict(
                            prop => map(
                                x -> parse(T, x), 
                                @view raw_data[3:(end-1)]
                            )
                        )
                    )
                )
            else
                # data is a value
                valfloat = tryparse(T, raw_data[2])
                mergewith!(
                    merge!, cache.data, 
                    Dict(
                        naif => Dict(
                            prop => T[valfloat !== nothing ? valfloat : tryparse(Int64, raw_data[2])]
                        )
                    )
                )
            end
        end
    end
    return cache
end

"""
    load_tpc(::Type{T}, file::String) where T 

Load TPC file in a [`PlanetaryConstantsDict`](@ref) object.
"""
function load_tpc(::Type{T}, file::String) where T 
    cache = PlanetaryConstantsDict{T}()
    return load_tpc!(cache, file)
end

function load_tpc(::Type{T}, files::AbstractVector{String}) where T 
    cache = PlanetaryConstantsDict{T}()
    for file in files
        load_tpc!(cache, file)
    end 
    return cache
end
