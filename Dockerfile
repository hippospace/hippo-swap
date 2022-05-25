FROM rust:1.60.0-slim-buster

# install updates and base packages
RUN apt-get update && apt-get install -y clang git curl pkg-config libssl-dev

# create the user for the runnign env
RUN useradd -ms /bin/bash hippo

# switch to the user
USER hippo

# install move and aptos cli
RUN cargo install --git https://github.com/move-language/move move-cli --branch main --features address32 && \
    git clone https://github.com/aptos-labs/aptos-core.git && cd aptos-core && \
    cargo bulid && \
    echo 'export PATH="/path/aptos-core/target/debug:$PATH"' >> ~/.profile && \
    source ~/.profile
