# Note: You can use any Debian/Ubuntu based image you want. 
ARG VARIANT="bookworm"
FROM mcr.microsoft.com/devcontainers/base:dev-${VARIANT}

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends make build-essential curl wget python3 python3-pip cmake coreutils jp2a dnsutils podman zsh

# Switch User to the user we will be running the devcontainer as
ARG USERNAME=vscode
USER $USERNAME
RUN sudo chown -R $USERNAME:$USERNAME /home/$USERNAME \
    && sudo mkdir -p /home/$USERNAME/bin \
    && sudo mkdir -p /home/$USERNAME/.local/state \
    && sudo mkdir -p /home/$USERNAME/.local/share \
    && sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.local/share \
    && sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.local/state

# bash and zsh history
ARG USERNAME=vscode
RUN printf '%s\n' "export HISTFILE=/commandhistory/.bash_history" "export PROMPT_COMMAND='history -a'" >> "/home/$USERNAME/.bashrc" \
    && printf '%s\n' "export HISTFILE=/commandhistory/.zsh_history" "export HIST_SAVE_BY_COPY=1" "setopt APPEND_HISTORY" "setopt INC_APPEND_HISTORY" >> "/home/$USERNAME/.zshrc"