"""
Methods for HMM for parsing reads of sequences. Currently works specifically for that.
"""

# Return viterbi path and log probability for that path. Takes logs of matrices.
function viterbi_logs(observations_given_states::Array{Float64, 2}, transitions::Array{Float64, 2}, initials::Array{Float64})
    numstates, numsteps = size(observations_given_states)
    scores = zeros(numstates, numsteps)
    paths = zeros(scores, UInt16)
    # Forward Score propogation
    scores[:, 1] = initials + observations_given_states[:, 1]
    for t in 2:numsteps
        for j in 1:numstates
            transitioned_scores = scores[:, t-1] + transitions[:, j]
            paths[j, t] = indmax(transitioned_scores)
            scores[j, t] = transitioned_scores[paths[j, t]] + observations_given_states[j, t]
        end
    end
    # Backtrack
    path = zeros(Int, numsteps)
    probs = zeros(path, Float64)
    path[end] = indmax(scores[:, end])
    probs[end] = scores[path[end], end]
    for t in numsteps-1:-1:1
        path[t] = paths[path[t+1], t+1]
        probs[t] = scores[path[t+1], t+1]
    end
    return path, maximum(scores[:, end])
end

"""Return 5x5 transition matrix with given transition probabilities
State 1 -- uniform observation distribution.
State 2 -- High "A" observation likelihood.
State 3 -- High "C" observation likelihood.
State 4 -- High "G" observation likelihood.
State 5 -- High "T" observation likelihood.
Each state has high return likelihood."""
function trans_mat(; uniform_cycle_prob = 0.9999999999, homopoly_cycle_prob = 0.98)
    uh_prob = (1-uniform_cycle_prob) / 4
    hu_prob = 1 - homopoly_cycle_prob
    T = [
        uniform_cycle_prob uh_prob uh_prob uh_prob uh_prob;
        
        hu_prob homopoly_cycle_prob 0 0 0;
        
        hu_prob 0 homopoly_cycle_prob 0 0;
        
        hu_prob 0 0 homopoly_cycle_prob 0;
        
        hu_prob 0 0 0 homopoly_cycle_prob;
    ]
    return T
end

"""Return 5x4 observation matrix with given probabilities.
State 1 -- uniform observation distribution.
State 2 -- High "A" observation likelihood.
State 3 -- High "C" observation likelihood.
State 4 -- High "G" observation likelihood.
State 5 -- High "T" observation likelihood."""
function obs_mat(; homopoly_prob = 0.99)
    uniform_prob = 0.25
    not_hpoly_prob = (1-homopoly_prob) / 3
    O = [
        uniform_prob uniform_prob uniform_prob uniform_prob;
        
        homopoly_prob  not_hpoly_prob not_hpoly_prob not_hpoly_prob;
        
        not_hpoly_prob homopoly_prob  not_hpoly_prob not_hpoly_prob;
        
        not_hpoly_prob not_hpoly_prob homopoly_prob  not_hpoly_prob;
        
        not_hpoly_prob not_hpoly_prob not_hpoly_prob homopoly_prob;
    ]
    return O
end

"""Initial state distributions: 5x1 vector"""
function initial_dist(; uniform_state = 0.99)
    not_unistate = (1 - uniform_state) / 4
    return [uniform_state; not_unistate; not_unistate; not_unistate; not_unistate]
end

"""Column index for each nucleotide in observation matrix."""
const NUCLEOTIDE_COLS = Dict('A' => UInt8(1),
                             'C' => UInt8(2),
                             'G' => UInt8(3),
                             'T' => UInt8(4));

"""Populate 5xT matrix with likelihood of observation at each time step given each state."""
function get_obs_given_state(observation_matrix::Array{Float64,2}, observation_seq::String)
    obs_given_state = zeros(length(observation_seq), 5)
    for (i, nuc) in enumerate(observation_seq)
        obs_given_state[i, :] = observation_matrix[:, NUCLEOTIDE_COLS[nuc]]
    end
    return transpose(obs_given_state)
end

homopolymer_filter(seqs::Array{String}) = homopolymer_filter(seqs, [], [])[1]
markov_filter = homopolymer_filter

"""Filter sequences with "bad" sections in the middle -- abnormally long runs of a single base, and trims bad ends."""
function homopolymer_filter(seqs::Array, phreds::Array, names::Array;
                       transmat = nothing, obsmat = nothing,
                       initialdist = nothing)
    newseqs, newphreds, newnames = String[], [], String[]
    phredsexist = length(phreds) == length(seqs)
    namesexist = length(names) == length(seqs)
    if (!phredsexist && length(phreds) > 0) || (!namesexist && length(names) > 0)
        error("Dimension mismatch in names or phreds array")
    end
    if transmat == nothing
        transmat = trans_mat()
    end
    if obsmat == nothing
        obsmat = obs_mat()
    end
    if initialdist == nothing
        initialdist = initial_dist()
    end
    T_logs, O_logs, i_logs = log.(transmat), log.(obsmat), log.(initialdist)
    for i in 1:length(seqs)
        seq = seqs[i]
        path = viterbi_logs(get_obs_given_state(O_logs, seq), T_logs, i_logs)[1]
        # remove bad parts
        lo = 1
        while lo < length(path) && path[lo] != 1
            lo += 1
        end
        hi = length(path)
        while hi > 0 && path[hi] != 1
            hi -= 1
        end
        if lo != 1 || hi != length(path)
            path = path[lo:hi]
        end
        # make sure no bad parts in middle
        ind = findnext(x->x != 1, path, lo)
        if ind > hi || ind == 0
            push!(newseqs, seq[lo:hi])
            if phredsexist
                push!(newphreds, phreds[i][lo:hi])
            end
            if namesexist
                push!(newnames, names[i])
            end
        end
    end
    # may return empty arrays for newphreds and newnames
    return newseqs, convert(Array{Array{Phred, 1}}, newphreds), newnames
end

"""Filter sequences with "bad" sections in the middle -- abnormally long runs of a single base, and trims bad ends.
Reads from sourcepath file and writes filtered sequences to destpath file."""
function homopolymer_filter(sourcepath::String, destpath::String;
                       transmat = nothing, obsmat = nothing,
                       initialdist = nothing, format="fastq")
    seqs, phreds, names = String[], Vector{Phred}[], String[]
    if format == "fastq"
        seqs, phreds, names = read_fastq(sourcepath, seqtype=String)
    elseif format == "fasta"
        names, seqs = read_fasta_with_names(sourcepath, seqtype=String)
    else
        println("Invalid format! File not written.")
    end
    println("Cleaning $(length(seqs)) sequences")
    newseqs, newphreds, newnames = markov_filter(seqs, phreds, names, 
                                                 transmat=transmat, obsmat=obsmat, 
                                                 initialdist=initialdist)
    println("Writing $(length(newseqs)) sequences")
    if format == "fastq"
        write_fastq(destpath, newseqs, newphreds, names=newnames, DNASeqType=false)
    else
        write_fasta(destpath, newseqs, names=newnames, DNASeqType=false)
    end     
end

"""Compute logs of forward scores. Takes logs of matrices."""
function forward_logs(observations_given_states::Array{Float64, 2}, transitions::Array{Float64, 2}, initials::Array{Float64})
    numstates, numsteps = size(observations_given_states)
    fwds = zeros(numstates, numsteps)
    # Forward pass - (unnormalized?) probs of states at time t given observations up to t
    fwds[:, 1] = initials + observations_given_states[:, 1]
    for t in 2:numsteps
        for j in 1:numstates
            prob_state_given_prev = reduce(logsum, fwds[:, t-1] + transitions[:, j])
            fwds[j, t] = prob_state_given_prev + observations_given_states[j, t]
        end
    end
    return fwds
end

"""Compute logs of backward scores and individual posterior probabilities. Takes logs of matrices."""
function backward_logs(observations_given_states::Array{Float64, 2}, transitions::Array{Float64, 2}, initials::Array{Float64})
    numstates, numsteps = size(observations_given_states)
    bwds = zeros(numstates, numsteps)
    # Backwards pass - (unnormalized?) probs of states at time t given observations after t
    bwds[:, end] = 1  # arbitrarily initialized
    log_posteriors = zeros(numstates, numsteps)
    for t in numsteps-1:-1:1
        for i in 1:numstates
            bwds[i, t] = reduce(logsum, bwds[:, t+1] + transitions[i, :] + observations_given_states[:, t+1])
        end
    end
    return bwds
end

"""Compute logs of forward-backward scores and individual probabilities. Takes logs of matrices."""
function forward_backward_logs(observations_given_states::Array{Float64, 2}, transitions::Array{Float64, 2}, initials::Array{Float64})
    numstates, numsteps = size(observations_given_states)
    fwds = forward_logs(observations_given_states, transitions, initials)
    bwds = zeros(numstates, numsteps)
    # Backwards pass - Compute manually to compute individual probabilities simultaneously
    bwds[:, end] = 1  # arbitrarily initialized
    log_posteriors = zeros(numstates, numsteps)
    for t in numsteps-1:-1:1
        for i in 1:numstates
            bwds[i, t] = reduce(logsum, bwds[:, t+1] + transitions[i, :] + observations_given_states[:, t+1])
        end
        # and combine with fwds to get posterior probability logs
        fb_probs = fwds[:, t] + bwds[:, t]
        norm = reduce(logsum, fb_probs)
        log_posteriors[:, t] = fb_probs - norm
    end
    # and for the end
    fb_probs = fwds[:, end] + bwds[:, end]
    norm = reduce(logsum, fb_probs)
    log_posteriors[:, end] = fb_probs - norm
    return log_posteriors
end

"""Generate a sequence given a model. Can create bad reads (long runs of a single base)"""
function gen_seq_with_model(n::Int, trans_mat, obs_mat, initial_dists)
    state_seq = zeros(Int, n)
    state_seq[1] = wsample(collect(1:5), trans_mat*initial_dists)
    obs_seq = wsample(["A", "C", "G", "T"], obs_mat[state_seq[1], :])
    for t in 2:n
        state_seq[t] = wsample(collect(1:5), trans_mat[state_seq[t-1], :])
        obs_seq *= wsample(["A", "C", "G", "T"], obs_mat[state_seq[t], :])
    end
    return obs_seq
end

"""Draw flagged sites with capital letters, safe sites with lowercase"""
function viterbiprint(s::String)
    obs = get_obs_given_state(obs_mat(), s)
    v = viterbi_logs(log.(obs),log.(trans_mat()),log.(initial_dist()))
    v = v[1]
    s = collect(s)
    for i in 1:length(v)
        if v[i]==1
            s[i] += 32
        end
    end
    return join(s)
end

