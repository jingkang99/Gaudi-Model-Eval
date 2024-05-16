# https://huggingface.co/blog/pretraining-bert

from huggingface_hub import notebook_login

from huggingface_hub import HfApi

user_id = HfApi().whoami()["name"]

print(f"user id '{user_id}' will be used during the example")

from datasets import concatenate_datasets, load_dataset

#  Prepare the dataset

bookcorpus = load_dataset("bookcorpus", split="train")
wiki = load_dataset("wikipedia", "20220301.en", split="train")
wiki = wiki.remove_columns([col for col in wiki.column_names if col != "text"])  # only keep the 'text' column

assert bookcorpus.features.type == wiki.features.type
raw_datasets = concatenate_datasets([bookcorpus, wiki])

# Train a Tokenizer

from tqdm import tqdm
from transformers import BertTokenizerFast

# repositor id for saving the tokenizer
tokenizer_id="bert-base-uncased-0511-24-habana"

# create a python generator to dynamically load the data
def batch_iterator(batch_size=10000):
    for i in tqdm(range(0, len(raw_datasets), batch_size)):
        yield raw_datasets[i : i + batch_size]["text"]

# create a tokenizer from existing one to re-use special tokens
tokenizer = BertTokenizerFast.from_pretrained("bert-base-uncased")

bert_tokenizer = tokenizer.train_new_from_iterator(text_iterator=batch_iterator(), vocab_size=32_000)
bert_tokenizer.save_pretrained("tokenizer")

# you need to be logged in to push the tokenizer
bert_tokenizer.push_to_hub(tokenizer_id)

#Preprocess the dataset

from transformers import AutoTokenizer
import multiprocessing

# load tokenizer
# tokenizer = AutoTokenizer.from_pretrained(f"{user_id}/{tokenizer_id}")
tokenizer = AutoTokenizer.from_pretrained("tokenizer")
num_proc = multiprocessing.cpu_count()
print(f"The max length for the tokenizer is: {tokenizer.model_max_length}")

def group_texts(examples):
    tokenized_inputs = tokenizer(
       examples["text"], return_special_tokens_mask=True, truncation=True, max_length=tokenizer.model_max_length
    )
    return tokenized_inputs

# preprocess dataset
tokenized_datasets = raw_datasets.map(group_texts, batched=True, remove_columns=["text"], num_proc=num_proc)
tokenized_datasets.features

from itertools import chain

# Main data processing function that will concatenate all texts from our dataset and generate chunks of
# max_seq_length.
def group_texts(examples):
    # Concatenate all texts.
    concatenated_examples = {k: list(chain(*examples[k])) for k in examples.keys()}
    total_length = len(concatenated_examples[list(examples.keys())[0]])
    # We drop the small remainder, we could add padding if the model supported it instead of this drop, you can
    # customize this part to your needs.
    if total_length >= tokenizer.model_max_length:
        total_length = (total_length // tokenizer.model_max_length) * tokenizer.model_max_length
    # Split by chunks of max_len.
    result = {
        k: [t[i : i + tokenizer.model_max_length] for i in range(0, total_length, tokenizer.model_max_length)]
        for k, t in concatenated_examples.items()
    }
    return result

tokenized_datasets = tokenized_datasets.map(group_texts, batched=True, num_proc=num_proc)
# shuffle dataset
tokenized_datasets = tokenized_datasets.shuffle(seed=34)

print(f"the dataset contains in total {len(tokenized_datasets)*tokenizer.model_max_length} tokens")
# the dataset contains in total 3417216000 tokens

# push dataset to hugging face
dataset_id=f"{user_id}/processed_bert_dataset"
tokenized_datasets.push_to_hub(f"{user_id}/processed_bert_dataset")


