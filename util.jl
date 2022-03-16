function writeSorted(file, dict, sortind)
    io = open(joinpath(@__DIR__, file), "w")
    writedlm(io, sort(collect(dict), by=x->x[sortind], rev=false))
    close(io)
end

function prompt(p)
    println(p)
    return chomp(readline())
end

#Prompts user to enter a valid attempt and returns it
function getUserAttempt(allowed, a)
    attempt = prompt("Enter round $(a) attempt:")
    validAttempt = attempt in allowed #Need to assign here instead of just making it a conditional while because of aforementioned VS Code bug
    while validAttempt == false
        attempt = prompt("Invalid attempt! Please enter a valid word:")
        validAttempt = attempt in allowed
    end
    println("Attempt Entered: $(attempt)")
    return attempt
end

#Prompts user to enter a valid output pattern and returns it
function getUserPattern()
    patternRegex = r"[BbGgYy]{5}"
    pattern = match(patternRegex, prompt("Enter resulting output: (5 letter combination using G(reen), Y(ellow), and B(lack))"))
    validPattern = pattern != nothing
    while validPattern == false
        pattern = match(patternRegex, prompt("Invalid output! Please enter a valid output:"))
        validPattern = pattern == nothing
    end
    println("Pattern Entered: $(pattern.match)")
    return pattern
end