const NUCLEOTIDE_BITS = Dict('A' => unsigned(0),
                       'C' => unsigned(1),
                       'G' => unsigned(2),
                       'T' => unsigned(3))

const KmerType = Array{UInt32, 1}

"""Count kmers in string"""
function kmer_count(str::String, k::Int)
    # TODO: could directly encode `str` as 2-bit BioSequence
    bins = zeros(eltype(KmerType), 4^k)

    mask = unsigned(4^k - 1)  # all ones
    kmer = unsigned(0)
    for c in str[1:k-1]
        kmer = (kmer << 2) + NUCLEOTIDE_BITS[c]
    end
    for c in str[k:end]
        kmer = ((kmer << 2) & mask) + NUCLEOTIDE_BITS[c]
        bins[kmer + 1] += 1
    end
    return bins
end

const AA_DICT = Dict('M'=>11,'I'=>8,'Y'=>20,'L'=>10,'*'=>0,'F'=>5,'Q'=>14,
    'D'=>3,'V'=>18,'E'=>4,'T'=>17,'H'=>7,'P'=>13,'G'=>6,'N'=>12,'K'=>9,'C'=>2,
    'R'=>15,'W'=>19,'A'=>1,'S'=>16,'X'=>22)


"""Counts amino acid kmers in string (in all reference frames).
k = length of kmer in amino acids.
Sparse and kinda slow"""
function sparse_aa_kmer_count(str::String, k::Int)
    bins = spzeros(UInt64, 21^k)
    kmer = unsigned(0)
    mask = unsigned(21) ^ k
    straas = generate_aa_seqs(str)
    for straa in straas
        for aa in straa[1:k-1]
            kmer = kmer * 21 + AA_DICT[aa]
        end
        for aa in straa[k:end]
            kmer = ((kmer * 21) % mask) + AA_DICT[aa]
            bins[kmer+1] += 1
        end
    end
    return bins
end

"""Compute distance function that is correct for small differences."""
function corrected_kmer_dist(kmers1::Array, kmers2::Array; k = nothing)
    if k == nothing
        k = Int(log(4, length(kmers1)))
    end
    return sqeuclidean(kmers1, kmers2)/ (k*(sum(kmers1) + sum(kmers2)))
end

"""Partial application to provide a two argument dist func"""
function corrected_kmer_dist(k::Int)
    function kdist(kmers1, kmers2)
        return corrected_kmer_dist(kmers1, kmers2, k=k)
    end
    return kdist
end

