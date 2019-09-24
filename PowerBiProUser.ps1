#Install-Module MSOnline -Force
#Install-Module AzureRm -Force -AllowClobber
#Install-Module -Name Az -AllowClobber -Force

Set-Location $PSScriptRoot
Get-Location

#$kubsecrets = '..\scripts\get-az-secret.bat'
#$data = & $kubsecrets environment
#$jsonData = ConvertFrom-Json $data -ErrorAction SilentlyContinue

$ServicePrincipalUsername = "3fc05167-d471-471f-ab13-b2e464190cfa"
$ServicePrincipalPassword = "d9oh6Wa9TAfVYloAbLn517WNw5FCA4+MgtjFV27IB+g="
$AzureTenantId = "774a1f21-ee4c-476c-8ed2-07c8e8c2e898"
$powerbiProUserAccount = "00UIAD1PBIPRO@powerschool.cloud"
$PowerBIAccountPassword = "PS_Insights@125"
$aduser = "uiadvaadadmin@powerschool.cloud"
$adpassword = "ZzVtKmKDrLkHbbOXxYiKCA=="


$SECURE_PASSWORD1 = ConvertTo-SecureString $ServicePrincipalPassword -AsPlainText -Force
$CREDENTIAL1 = New-Object System.Management.Automation.PSCredential ($ServicePrincipalUsername, $SECURE_PASSWORD1)
Login-AzureRmAccount -ServicePrincipal -Credential $CREDENTIAL1 -Tenant $AzureTenantId

#clear the azure rm context cache and connect azure ad with the ad user
Clear-AzureRmContext -Scope CurrentUser -Force
$SECURE_PASSWORD = ConvertTo-SecureString $adpassword -AsPlainText -Force
$CREDENTIAL = New-Object System.Management.Automation.PSCredential ($aduser, $SECURE_PASSWORD)
Connect-AzureAD -Credential $CREDENTIAL

If ($error) {
    Throw "Deployment failed. Check the credentials."
}

if (!(Get-AzureADUser -Filter "userPrincipalName eq '$($powerbiProUserAccount)'" -ErrorAction SilentlyContinue)) {
    # create new azure AD user
    $PasswordProfile = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
    $PasswordProfile.Password = $PowerBIAccountPassword
    $PasswordProfile.EnforceChangePasswordPolicy = $False
    $PasswordProfile.ForceChangePasswordNextLogin = $False
    # create new azure ad powerbi pro user
    New-AzureADUser -DisplayName $powerbiProUserAccount -PasswordProfile $PasswordProfile -UserPrincipalName $powerbiProUserAccount -AccountEnabled $true -MailNickName "PowerBIProAccount"
    Start-Sleep -s 150
}
else {
    Write-Host "PowerBI Pro User already exists, therefore skipping the stage. "
}

if (Get-AzureADUser -Filter "userPrincipalName eq '$($powerbiProUserAccount)'" -ErrorAction SilentlyContinue) {
   
    Get-AzureADUser -ObjectId $powerbiProUserAccount | Set-AzureADUser -PasswordPolicies DisablePasswordExpiration
    # Fetch user to assign to role
    $roleMember = Get-AzureADUser -ObjectId $powerbiProUserAccount
    # Fetch User Account Administrator role instance
    $role = Get-AzureADDirectoryRole | Where-Object { $_.displayName -eq 'Power BI Service Administrator' }
    try {
        # Add user to role
        Add-AzureADDirectoryRoleMember -ObjectId $role.ObjectId -RefObjectId $roleMember.ObjectId
    }
    catch {
        Write-host "User already added to the ad directory role."
    }
    # Connect to Msol service with the ad user
    Connect-MsolService -credential $CREDENTIAL
    # Get the Tenant name so we can automate the license assignment.
    $MSOLAccountSKU = Get-MsolAccountSku | Where-Object { $_.AccountSkuID -like '*:POWER_BI_PRO' }
    $TenantName = $MSOLAccountSKU.AccountName
    
    try {
        # set usage locaton for the user
        $ProUserObjectId = $roleMember.ObjectId
        Set-MsolUser -ObjectId $ProUserObjectId -UsageLocation US 
        #set license for the user
        Set-MsolUserLicense -UserPrincipalName $powerbiProUserAccount -AddLicenses $TenantName":POWER_BI_PRO" 
    
        #get the licensed user status
        $licensedUser = Get-MsolUser -UserPrincipalName $powerbiProUserAccount
        Write-Host "Log to check whether the newly created pro user is successfully licensed or not. Check the status here : '$licensedUser"

    }
    catch {
        Write-host "User already assigned powerbipro license. "
    }
}
else {
    Throw "User does not exists. Go ahead and re create the user "
}

