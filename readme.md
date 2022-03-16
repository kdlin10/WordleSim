# WordleSim

Just a simple interactive Wordle solver and collection of related functions in Julia. 

"Cheats" with foreknowledge of the set of possible answers extracted from NYT Wordle. Scores attempts by the average information gained/reduction in possible answers next round via filtering out eliminated possibilities (locally greedy).

`WordleSim.startSolver()` to start

`WordleSim.scoreAttempts()` - Writes sorted list of attempts and their scores against the set of answers

`WordleSim.producePattern(attempt, answer)` - Returns the output pattern of an attempt against an answer (5 Char Vector)

`WordleSim.patternTest(attempt, pattern, answer)` - Returns true if answer is a possibility given the output pattern of an attempt

`WordleSim.makeAttempts(attempts, answers, depth)` - Returns average uncertainty remaining by each possible attempt against the set of answers

`WordleSim.tryAnswer(attempt, answers, depth)` - Returns average information gained/uncertainty reduced by our attempt against the set of answers
