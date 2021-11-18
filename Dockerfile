FROM ubuntu:latest

# RUN apk add --no-cache grub xorriso
RUN apt-get update \
    && apt-get install -y --no-install-recommends grub2 xorriso \
    && rm -rf /var/lib/apt/lists/*
    
WORKDIR /mount