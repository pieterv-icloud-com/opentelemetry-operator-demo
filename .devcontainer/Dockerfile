# Note: You can use any Debian/Ubuntu based image you want. 
ARG VARIANT="bookworm"
FROM mcr.microsoft.com/devcontainers/base:dev-${VARIANT}

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends make build-essential curl wget python3 python3-pip cmake coreutils jp2a dnsutils podman

# Switch User to the user we will be running the devcontainer as
ARG USERNAME=vscode
USER $USERNAME
RUN sudo chown -R $USERNAME:$USERNAME /home/$USERNAME \
    && sudo mkdir -p /home/$USERNAME/bin \
    && sudo mkdir -p /home/$USERNAME/.local/state \
    && sudo mkdir -p /home/$USERNAME/.local/share \
    && sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.local/share \
    && sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.local/state

# bash history
ARG USERNAME=vscode
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    && echo $SNIPPET >> "/home/$USERNAME/.bashrc"   