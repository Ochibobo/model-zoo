# # Language detection (character-level)

# In this example, we create a character-level language detection model. Given a sentence (text), each character is fed into an [LSTM](https://d2l.ai/chapter_recurrent-modern/lstm.html) and then the final output determines in which language the text is written. 

# This example illustrates the preprocessing of text data before feeding it into the model as well as the use of a scanner and an encoder for a language model. 

# If you need more information about how LSTM work and related technical concepts, 
# check out the following resources:

# * [The Unreasonable Effectiveness of Recurrent Neural Networks](http://karpathy.github.io/2015/05/21/rnn-effectiveness/)
# * [Understanding LSTM Networks](https://colah.github.io/posts/2015-08-Understanding-LSTMs/)
# * [Illustrated Guide to Recurrent Neural Networks: Understanding the Intuition](https://www.youtube.com/watch?v=LHXXI4-IEns)

# To run this example, we need the following packages:

using Flux
using Flux: onehot, onehotbatch, logitcrossentropy, reset!, throttle
using Statistics: mean
using Random
using Unicode
using Parameters: @with_kw

# We set default values for hyperparameters:

@with_kw mutable struct Args
    lr::Float64 = 1e-3     ## Learning rate
    N::Int = 15            ## Number of perceptrons in hidden layer
    test_len::Int = 100    ## length of test data
    langs_len::Int = 0     ## Number of different languages in Corpora
    alphabet_len::Int = 0  ## Total number of characters possible, in corpora
    throttle::Int = 10     ## throttle timeout
end

# ## Load dataset

# Before running this example, you need to obtain the data by running the script `scrape.jl`. 
# It downloads articles from Wikipedia in five different languages (English, Italian, French, Spanish, and Danish). 
# Also, it creates the folder `corpus` that contains five text files (one per language).

# The function `get_processed_data` reads the text files and creates the data set for training the model. 
# First, it loads the raw text into a dictionary. 
# Then, it defines the alphabet and the characters that will be represented as unknown. 
# Finally, it one-hot encodes the text and its corresponding labels (the language in which is written) 
# before splitting the data into train and test data sets.


function get_processed_data(args)
    corpora = Dict()

    for file in readdir("corpus")
        lang = Symbol(match(r"(.*)\.txt", file).captures[1])
        corpus = split(String(read("corpus/$file")), ".")
        corpus = strip.(Unicode.normalize.(corpus, casefold=true, stripmark=true))
        corpus = filter(!isempty, corpus)
        corpora[lang] = corpus
    end

    langs = collect(keys(corpora))
    args.langs_len = length(langs)
    alphabet = ['a':'z'; '0':'9'; ' '; '\n'; '_']
    args.alphabet_len = length(alphabet)

    ## See which chars will be represented as "unknown"
    unique(filter(x -> x ∉ alphabet, join(vcat(values(corpora)...))))

    dataset = [(onehotbatch(s, alphabet, '_'), onehot(l, langs)) for l in langs for s in corpora[l]] |> shuffle

    train, test = dataset[1:end-args.test_len], dataset[end-args.test_len+1:end]
    return train, test
end

# ## Create the model

# The model consists of a **scanner** and an **encoder**. The **scanner** reads the sentence one character 
# at a time using one [dense](https://fluxml.ai/Flux.jl/stable/models/layers/#Flux.Dense) 
# and one [LSTM](https://fluxml.ai/Flux.jl/stable/models/layers/#Flux.LSTM) layers. 
# Once all of the text has been scanned, the **encoder** outputs the predicted language for the sentence.



function build_model(args)
    scanner = Chain(Dense(args.alphabet_len, args.N, σ), LSTM(args.N, args.N))
    encoder = Dense(args.N, args.langs_len)
    return scanner, encoder
end
 
# Notice that we use the function [reset!](https://fluxml.ai/Flux.jl/stable/models/layers/#Flux.reset!) 
# when computing the model's prediction to reset the hidden state of an LSTM layer back to its original value.


function model(x, scanner, encoder)
    state = scanner.(x.data)[end]
    reset!(scanner)
    encoder(state)
end

# ## Train the model

# The function `train` executes one training step for the model 
# using Flux’s [train!](https://fluxml.ai/Flux.jl/stable/training/training/#Flux.Optimise.train!). 
# It uses the loss function 
# [logitcrossentropy](https://fluxml.ai/Flux.jl/stable/models/losses/#Flux.Losses.logitcrossentropy) 
# and the [ADAM](https://fluxml.ai/Flux.jl/stable/training/optimisers/#Flux.Optimise.ADAM) optimizer. 
# Also, it creates a callback function to output the test loss as defined in the args object.   


function train(; kws...)
    ## Initialize Hyperparameters
    args = Args(; kws...)
    
    ## Load Data
    train_data, test_data = get_processed_data(args)

    @info("Constructing Model...")
    scanner, encoder = build_model(args)

    loss(x, y) = logitcrossentropy(model(x, scanner, encoder), y)
    testloss() = mean(loss(t...) for t in test_data)
    
    opt = ADAM(args.lr)
    ps = params(scanner, encoder)
    evalcb = () -> @show testloss()
    @info("Training...")
    Flux.train!(loss, ps, train_data, opt, cb = throttle(evalcb, args.throttle))
end

cd(@__DIR__)
train()
