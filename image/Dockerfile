FROM mcr.microsoft.com/dotnet/sdk:6.0-focal

ARG HTTP_PORT_RANGE=1100-1200

ENV HOME=/home/user
# Opt out of telemetry until after we install jupyter when building the image, this prevents caching of machine id
ENV DOTNET_INTERACTIVE_CLI_TELEMETRY_OPTOUT=true

# Install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)

ENV DEBIAN_FRONTEND noninteractive
ENV POWERSHELL_TELEMETRY_OPTOUT=true

RUN mkdir /notebooks ${HOME} && \
    for f in "${HOME}" "/etc/passwd" "/notebooks"; do \
      echo "Changing permissions on ${f}" && chgrp -R 0 ${f} && \
      chmod -R g+rwX ${f}; \
    done

ADD entrypoint.sh /
ADD okd.ipynb variables.ps1 /notebooks

RUN apt-get update \
    && apt-get install -yq --no-install-recommends \
    wget \
    bzip2 \
    ca-certificates \
    sudo \
    locales \
    fonts-liberation \
    run-one \
    python3.8 \
    python3-pip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

RUN python3 -m pip install setuptools
RUN python3 -m pip install jupyter
RUN python3 -m pip install jupyterlab

# Add package sources
RUN dotnet nuget add source "https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-tools/nuget/v3/index.json" -n "dotnet-tools"
RUN dotnet nuget add source "https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet5/nuget/v3/index.json" -n "dotnet5"
RUN dotnet nuget add source "https://pkgs.dev.azure.com/dnceng/public/_packaging/MachineLearning/nuget/v3/index.json" -n "MachineLearning"

# Install lastest build from master branch of Microsoft.DotNet.Interactive
RUN dotnet tool install --tool-path /usr/share/dotnet-interactive Microsoft.dotnet-interactive --add-source "https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-tools/nuget/v3/index.json"
RUN ln -s /usr/share/dotnet-interactive/dotnet-interactive /usr/bin/dotnet-interactive
RUN dotnet interactive jupyter install --http-port-range ${HTTP_PORT_RANGE}

RUN pwsh -NoLogo -NoProfile -Command " \
    \$ErrorActionPreference = 'Stop' ; \
    \$ProgressPreference = 'SilentlyContinue' ; \
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted ; \
    Install-Module -Scope AllUsers VMware.PowerCLI ; \
    Set-PowerCLIConfiguration -Scope AllUsers -ParticipateInCeip:\$false -Confirm:\$false"

RUN for f in "${HOME}"; do \
      echo "Changing permissions on ${f}" && chgrp -R 0 ${f} && \
      chmod -R g+rwX ${f}; \
    done

EXPOSE 8888

WORKDIR /notebooks

ENTRYPOINT ["/entrypoint.sh"]
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--allow-root", "--notebook-dir=/notebooks/"]
