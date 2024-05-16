import os
import sys
import subprocess

DATASET = os.environ['DATASET']

import torch
import torchvision
import torch.nn as nn

#subprocess.check_call([sys.executable, '-m', 'pip', 'install', 
#'numpy', ' pandas', ' scikit-learn', 'datasets', 'optimum.habana', '--user'])

import pandas as pd
import numpy as np
from transformers import AutoConfig, AutoTokenizer, AutoModelForSequenceClassification, pipeline
from optimum.habana import GaudiConfig, GaudiTrainer, GaudiTrainingArguments
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score
from datasets import Dataset

def load_data():
    df = pd.read_csv(
        '/sox/data-ml/FinancialPhraseBank-v1.0/Sentences_50Agree.txt',
        sep='@',
        names=['sentence', 'label'],
        encoding = "ISO-8859-1")
    df = df.dropna()
    df['label'] = df['label'].map({"neutral": 0, "positive": 1, "negative": 2})
    df.head()

    df_train, df_test, = train_test_split(df, stratify=df['label'], test_size=0.1, random_state=42)
    df_train, df_val = train_test_split(df_train, stratify=df_train['label'],test_size=0.1, random_state=42)

    dataset_train = Dataset.from_pandas(df_train, preserve_index=False)
    dataset_val = Dataset.from_pandas(df_val, preserve_index=False)
    dataset_test = Dataset.from_pandas(df_test, preserve_index=False)

    return dataset_train, dataset_val, dataset_test


def compute_metrics(eval_pred):
    predictions, labels = eval_pred
    predictions = np.argmax(predictions, axis=1)
    return {'accuracy': accuracy_score(predictions, labels)}


def main():
    dataset_train, dataset_val, dataset_test = load_data()

    bert_model = AutoModelForSequenceClassification.from_pretrained('bert-large-uncased', num_labels=3)
    bert_tokenizer = AutoTokenizer.from_pretrained('bert-large-uncased')

    dataset_train = dataset_train.map(lambda e: bert_tokenizer(e['sentence'], truncation=True, padding='max_length', max_length=128), batched=True)
    dataset_val = dataset_val.map(lambda e: bert_tokenizer(e['sentence'], truncation=True, padding='max_length', max_length=128), batched=True)
    dataset_test = dataset_test.map(lambda e: bert_tokenizer(e['sentence'], truncation=True, padding='max_length' , max_length=128), batched=True)

    dataset_train.set_format(type='torch', columns=['input_ids', 'token_type_ids', 'attention_mask', 'label'])
    dataset_val.set_format(type='torch', columns=['input_ids', 'token_type_ids', 'attention_mask', 'label'])
    dataset_test.set_format(type='torch', columns=['input_ids', 'token_type_ids', 'attention_mask', 'label'])

    args = GaudiTrainingArguments(
        output_dir=DATASET + '/trained-llm/finbert-lm',
        overwrite_output_dir=True, 
        evaluation_strategy='epoch',
        save_strategy='no',
        logging_strategy='epoch',
        logging_dir= DATASET + '/log/',
        report_to='tensorboard',

        learning_rate=2e-5,
        per_device_train_batch_size=8,
        per_device_eval_batch_size=4,
        num_train_epochs=5,
        weight_decay=0.01,
        metric_for_best_model='accuracy',

        use_habana=True,                        # use Habana device
        use_lazy_mode=True,                     # use Gaudi lazy mode
        use_hpu_graphs=True,                    # set value for hpu_graphs
        gaudi_config_name='gaudi_config.json',  # load config file
    )

    trainer = GaudiTrainer(
        model=bert_model,                   # the instantiated 🤗 Transformers model to be trained
        args=args,                          # training arguments, defined above
        train_dataset=dataset_train,        # training dataset
        eval_dataset=dataset_val,           # evaluation dataset
        compute_metrics=compute_metrics
    )

    trainer.train()   
    
    trainer.save_model("/sox/data-ml/trained-llm/finbert-lm")

    trainer.predict(dataset_train, metric_key_prefix="train").metrics
    trainer.predict(dataset_test).metrics

    torch.jit._state.disable()
    device=torch.device('hpu')  
    pipe = pipeline("text-classification", model=bert_model, tokenizer=bert_tokenizer, device=device)

    print(pipe("Alabama Takes From the Poor and Gives to the Rich"))
    print(pipe("Economists are predicting the highest rate of employment in 15 years"))
    print(pipe("It’s Been a Poor Year So Far for Municipal Bonds"))
    print(pipe("Lavish Money Laundering Schemes Exposed in Canada"))
    print(pipe("Stocks edge lower as bank earnings add to concerns about the economy"))

if __name__ == '__main__':
    main()
