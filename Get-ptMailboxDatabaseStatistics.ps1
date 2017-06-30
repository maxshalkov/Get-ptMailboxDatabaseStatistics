function Get-ptMailboxDatabaseStatistics {
<#
    .SYNOPSIS
        Вывод информации по базам данных

    .DESCRIPTION
        Возвращает сведения по базам данных
    
    .EXAMPLE
        Get-ptMailboxDatabaseStatistics -Name Database01
    
    .PARAMETER Name
        Имя базы данных

    .NOTES
        Author: maxshalkov
#>

[CmdletBinding()]
param(
    [parameter(Mandatory=$false,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
    [system.string]$Name = "*"
)

begin{

    $Domain = $env:USERDNSDOMAIN -split "\." # or other domain

    $Searcher = [ADSISearcher]"(&(objectclass=group)(cn=psconfig))"  
    $Searcher.SearchRoot = "LDAP://DC=$($Domain[0]),DC=$($Domain[1])"
    $Searcher.PropertiesToLoad.Add("info") | Out-Null
    $psconfig_path = ($Searcher.FindAll().properties.info -split "\n")[0].trim()

    if (-not ($psconfig = Get-Content $psconfig_path -ErrorAction SilentlyContinue | ConvertFrom-Json)){
        throw "__pterror: Файл глобальных настроек недоступен"
    }

    if (-not (Test-Connection $psconfig.mailserver -Quiet)){
        throw "__pterror: $($psconfig.mailserver) недоступен"
    }

    $CommandList = "Get-MailboxDatabase","Get-Mailbox"
    $SessionProperties = @{
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = "http://$($psconfig.mailserver)/powershell"
        Authentication    = 'Kerberos'
    }

    try{
        $Session = New-PSSession @SessionProperties -ErrorAction Stop
        Import-PSSession $Session -CommandName $CommandList -AllowClobber | Out-Null 
    }
    catch{
        throw "__pterror: Ошибка создания сессии"
    }
}

process{
    ${*} = {
        param($Data)
        Write-Output ($Data -replace '^.+\((.+\))','$1' -replace '\D' -as [long])
    }

    $Out = Get-MailboxDatabase $Name -Status | 
        Select-Object Name,`
                      @{l="DatabaseSize";e={& ${*} -Data $_.DatabaseSize}},`
                      @{l="AvailableNewMailboxSpace";e={& ${*} -Data $_.AvailableNewMailboxSpace}},`
                      @{l="CountMailbox";e={(Get-Mailbox -Database $_.name).count}},
                      @{l="FactDatabaseSize";e={(& ${*} -Data $_.DatabaseSize) - (& ${*} -Data $_.AvailableNewMailboxSpace)}}

}

end{
    Remove-PSSession $Session
    return $Out
}
 
}