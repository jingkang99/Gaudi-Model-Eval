from optimum.habana.diffusers import GaudiDDIMScheduler, GaudiStableDiffusionPipeline


model_name = "stabilityai/stable-diffusion-2-1"

scheduler = GaudiDDIMScheduler.from_pretrained(model_name, subfolder="scheduler")

pipeline = GaudiStableDiffusionPipeline.from_pretrained(
    model_name,
    scheduler=scheduler,
    use_habana=True,
    use_hpu_graphs=True,
    gaudi_config="Habana/stable-diffusion-2",
)

outputs = pipeline(
    ["An image of a squirrel in Picasso style"],
    num_images_per_prompt=10,
    batch_size=2,
    height=768,
    width=768,
)

for i, image in enumerate(outputs.images):
    image.save(f"image_{i+1}.png")

#real	3m49.847s
#user	8m46.764s
#sys	35m38.455s
