FROM mcr.microsoft.com/powershell
RUN mkdir scripts
RUN cd scripts
RUN mkdir reports
RUN mkdir logs

COPY CronJobScript.ps1 /scripts


CMD  ["pwsh", "/scripts/CronJobScript.ps1"]
ENTRYPOINT ["pwsh", "-c"]
