module WordleSim
#An interactive Wordle solver and collection of related functions
#We have a set of valid *attempts* that can be tested against a hidden *answer* to generate an output *pattern* that provides clues to the answer

export startSolver, scoreAttempts, producePattern, patternTest, makeAttempts, tryAnswer, answers, allowed

include("util.jl")
using DelimitedFiles
using InlineStrings

const baseDir = @__DIR__
const answerFile = "wordle-answers-alphabetical.txt"
const allowedFile = "allowed.txt" #Disjoint set with answers - needs to be combined for full set of valid attempts
const freqCount = Dict{Char, Float64}() #Tracks occurrences of a letter, reuse to avoid constant reallocation... Float to track negative/positive zero
answers = Set(readdlm(joinpath(baseDir, answerFile), String7))
allowed = Set(union(answers, readdlm(joinpath(baseDir, allowedFile), String7)))

#Returns average uncertainty remaining by each possible attempt against the set of answers
function makeAttempts(attempts::Set{T}, answers::Set{T}, depth::Int) where T<:AbstractString
    if length(answers) == 0 || length(attempts) == 0 || depth > 6
        return Dict{T, Float64}("" => 0)
    end
    attemptRecords = Dict{T, Float64}()
    sizehint!(attemptRecords, length(attempts))
    @inbounds for attempt in attempts 
        attemptResults::Float64 = tryAnswer(attempt, answers, depth)
        push!(attemptRecords, attempt => attemptResults)
    end
    return attemptRecords
end

#Returns average information gained/uncertainty reduced in all possible universes by our attempt against set of answers
function tryAnswer(attempt::T, answers, depth::Int) where T<:AbstractString
    if depth > 6
        return 0.0
    end
    n = 0.0
    startEntropy = log(2, length(answers))
    cumInfogain = 0.0
    @inbounds for pattern in unique(collect(producePattern(attempt, ans) for ans in answers))
        numAnswers = length(filterAnswers(attempt, answers, pattern, freqCount))
        if numAnswers == length(answers) #Nothing filtered out = no info gained - ignore, means repeated input
            continue
        else #Should be impossible to have zero answers, since all patterns are generated against our set of answers
            #simUniverse = makeAttempts(filter(a -> a != attempt, allowed), filteredAnswers, depth + 1)
            cumInfogain += numAnswers * (startEntropy - log(2, numAnswers)) #+ sum(values(simUniverse))/length(simUniverse))
            n += numAnswers
        end
    end
    if n == 0.0
        return 0.0::Float64
    else
        return cumInfogain/n::Float64 
    end
end

function rankAttempts(aps::Vector{Tuple{T, Vector{}}}) where T <: AbstractString
    uncertainty = Vector{Tuple{Float64, T, T}}(undef, length(aps) * length(aps))
    #O(N^2)...
    n = 0
    @inbounds for i1 in eachindex(aps)
        for i2 in Iterators.drop(eachindex(aps), i1)
            n += 1
            uncertainty[n] = (getSharedUncertainty((aps[i1][2]), (aps[i2][2])), aps[i1][1], aps[i2][1])
        end
    end
    return view(uncertainty, 1:n)
end

#Calculate average shared uncertainty remaining between two Attempt-Pattern universes
function getSharedUncertainty(ap1, ap2) where T <: AbstractString
    uncertainty = Vector{Int}(undef, length(ap1) * length(ap2))
    n = 1
    @inbounds for i in eachindex(ap1)
        for j in eachindex(ap2)
            uncertainty[n] = length(filter(x -> (x in ap1[i])::Bool, ap2[j])) #Only need amount of intersections
            n += 1
        end
    end
    filter!(x -> x != 0, uncertainty) #zero intersections = impossible pattern combo, disregard
    return (sum(uncertainty .* broadcast(log, 2, uncertainty)) / sum(uncertainty))::Float64
end

function genAttemptsPatternCombos(attempts::Set{T}, answers::Set{T}) where T<:AbstractString
    attemptPatternResults = Vector{Tuple{T, Vector{}}}(undef, length(attempts))
    i = 1
     @inbounds for attempt in attempts
        attemptPatternResults[i] = (attempt, getAttemptAnswers(attempt, answers))
        i += 1
     end
     return attemptPatternResults
end

#Generate sets of sets of possible answers remaining for each possible pattern against our pool of answers
#Is it faster to keep the pattern to compare attempt-pattern combos for possible overlap vs just filtering?
function getAttemptAnswers(attempt::T, answers) where T<:AbstractString
    patterns = unique(collect(producePattern(attempt, ans) for ans in answers))
    patternOutcomes = Vector{Vector{T}}(undef, length(patterns))
    @inbounds for i in eachindex(patterns)
        patternOutcomes[i] = filterAnswers(attempt, answers, patterns[i], freqCount)
    end
    return patternOutcomes
end

#Generate all 3^5 (243) possible permutations of green, yellow, black over 5 spaces
function genAllPatterns()
    options = ('g', 'y', 'b')
    map(t -> collect(t), unique(collect(Iterators.product(options, options, options, options, options))))
end

#Produces (a) pattern output of an attempt against answer
function producePattern(attempt, answer)
    retPattern = ['b', 'b', 'b', 'b', 'b']
    #Produce Green, then Yellow - remainder is black
    @inbounds for i in eachindex(answer)
        if answer[i] == attempt[i]
            retPattern[i] = 'g'
            continue
        end
        for j in eachindex(attempt)
            if answer[i] == attempt[j] && i != j &&answer[j] != attempt[j] && retPattern[j] == 'b' 
                retPattern[j] = 'y'
                break
            end
        end
    end
    return retPattern
end

#Returns true if answer passes requirements vs given attempt and pattern - looks for reasons to return false
function patternTest(attempt::T, pattern, answer::T) where T <: AbstractString
    for i in eachindex(attempt)
        if (pattern[i] == 'g' && answer[i] != attempt[i]) || (answer[i] == attempt[i] && pattern[i] != 'g')
            return false
        elseif pattern[i] == 'y' #Yellow = +1 minimum amount elsewhere, ok to have more - fails if too few letters
            foundLetter = false
            sweepPos = 1
            for j in eachindex(answer)
                if answer[j] == attempt[i] && pattern[j] != 'g' #Found a match for yellow that isn't green
                    foundLetter = true
                    for k = sweepPos:i-1 #Don't worry about previous matches, returns false later if we have too few instances of the letter
                        if attempt[k] == attempt[i] && pattern[k] == 'y' #Match in position j is already spoken for
                           sweepPos = k + 1 #Start where we left off next match, not recount
                           foundLetter = false
                           break
                        end
                    end
                end
                if foundLetter == true #Found unreserved match
                    break
                end
            end
            if foundLetter == false
                return false
            end
        elseif pattern[i] == 'b' #Black = no instances except as required by yellow/green - fails if too many occurrences
            foundLetter = false
            sweepPos = 1
            for j in eachindex(answer) #Try to match presence of letter vs green/yellows - if excessive, return false
                if attempt[i] == answer[j] && pattern[j] != 'g'
                    foundLetter = true
                    for k = sweepPos:5
                        if attempt[k] == attempt[i] && pattern[k] == 'y'
                            sweepPos = k + 1
                            foundLetter = false
                            break
                        end
                    end
                end
                if foundLetter == true
                    return false
                end
            end
        end
    end
    return true
end

#Return all answers given an attempt, pattern, and answers pool
#Most time taken up by filtering - modified Direct Acyclical Word Graph as solution?
@views function filterAnswers(attempt::T, answers::Set{T}, pattern, freqCount::Dict{Char, Float64}) where T <: AbstractString
    retAnswers = collect(answers)::Vector{T}
    @inbounds for i in eachindex(attempt) #Initializing vs blind push with get + default value is pretty much the same performance
        push!(freqCount, attempt[i] => 0.0)
    end
    @inbounds for i in eachindex(pattern)
        l = attempt[i]
        if pattern[i] == 'g' #Green - Must be the same
            filter!(ans -> ans[i] == l, retAnswers)
            freqCount[l] += copysign(1, freqCount[l])
        elseif pattern[i] == 'y' #Yellow - Must NOT have one in the specific position
            filter!(ans -> ans[i] != l, retAnswers)
            freqCount[l] += copysign(1, freqCount[l])
        elseif signbit(freqCount[l]) == false #Black - No instances in any position beyond amount required by Green/Yellow, track presence by negative sign        
            freqCount[l] = copysign(freqCount[l], -1)
        end
    end
    @inbounds for (letter::Char, c::Int) in freqCount
        if c == 0 #Letter is Black without another instance marked Green/Yellow
            filter!(ans -> !contains(ans, letter), retAnswers)
        elseif signbit(c) == false #No black
            filter!(ans -> count(l -> l == letter, ans) >= c, retAnswers) 
        else #Presence of both Black and Yellow/Green constricts frequency to single value
            filter!(ans -> count(l -> l == letter, ans) == -c, retAnswers)
        end
    end
    @inbounds for k::Char in keys(freqCount)
        delete!(freqCount, k)
    end
    return retAnswers
end

#Interactive Wordle Solver
function startSolver() #VS Code Julia REPL has a bug with readline... https://github.com/julia-vscode/julia-vscode/issues/785 
    answers = Set(readdlm(joinpath(baseDir, answerFile), String7))
    allowed = Set(union(answers, readdlm(joinpath(baseDir, allowedFile), String7)))
    a = 1
    cont = true
    attempt = ""
    pattern = ""
    while cont
        attempt = getUserAttempt(allowed, a)
        pattern = getUserPattern()
        answers = Set(filterAnswers(String7(attempt), answers, lowercase(pattern.match), freqCount)) 
        println("$(length(answers)) remaining possible answers: ")
        for ans in answers
            print("$(ans) ")
        end
        println()
        if length(answers) <= 1
            cont = false
            println("Solution found!")
            break
        end
        println()
        attemptScores = makeAttempts(allowed, answers, 0)
        nextAttempt = recommended!(attemptScores, answers)
        println("Recommended next attempt: $(nextAttempt)")
        println()
        a += 1
    end
end

#Returns the highest scored attempt; prioritizes attempts that are in the answer set if there is a tie
function recommended!(attemptScores, answers)
    attemptScores = sort(collect(attemptScores), by=x->x[2], rev=true) 
    filter!(att -> att[2] == attemptScores[1][2], attemptScores)
    nextAttempt = attemptScores[1]
    for (attempt, _) in attemptScores
        if attempt in answers
            nextAttempt = attempt
            break
        end
    end
    return nextAttempt
end

#Writes naive information content of each possible attempt to file
function scoreAttempts()
    answers = Set(readdlm(joinpath(baseDir, answerFile), String7))
    allowed = Set(union(answers, readdlm(joinpath(baseDir, allowedFile), String7)))
    scores = makeAttempts(allowed, answers, 0)
    writeSorted("attempt scores.txt", scores, 2)
end

startSolver()

end