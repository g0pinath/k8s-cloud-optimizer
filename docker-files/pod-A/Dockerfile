FROM mcr.microsoft.com/powershell
RUN mkdir scripts
CMD  ["pwsh", "/scripts/ScaleUp-DownVMs.ps1"]
COPY ScaleUp-DownVMs.ps1 /scripts
COPY InputCSV.csv /scripts   

CMD  ["pwsh", "/scripts/ScaleUp-DownVMs.ps1"]
ENTRYPOINT ["pwsh", "-c"]
