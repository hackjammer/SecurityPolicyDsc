
Import-Module -Name (Join-Path -Path ( Split-Path $PSScriptRoot -Parent ) `
-ChildPath 'SecurityPolicyResourceHelper\SecurityPolicyResourceHelper.psm1') `
-Force

$script:localizedData = Get-LocalizedData -ResourceName 'MSFT_AccountPolicy'
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name
    )

    $returnValue = @{}
    $currentSecurityPolicy = Get-SecurityPolicy -Area SECURITYPOLICY
    $accountPolicyData = Get-PolicyOptionData -FilePath $("$PSScriptRoot\AccountPolicyData.psd1").Normalize()
    $accountPolicyList = Get-PolicyOptionList -ModuleName MSFT_AccountPolicy

    foreach ( $accountPolicy in $accountPolicyList )
    {
        Write-Verbose $accountPolicy
        $section = $accountPolicyData.$accountPolicy.Section
        Write-Verbose -Message ( $script:localizedData.Section -f $section )
        $valueName = $accountPolicyData.$accountPolicy.Value
        Write-Verbose -Message ( $script:localizedData.Value -f $valueName )
        $options = $accountPolicyData.$accountPolicy.Option
        Write-Verbose -Message ( $script:localizedData.Option -f $($options -join ',') )
        $currentValue = $currentSecurityPolicy.$section.$valueName
        Write-Verbose -Message ( $script:localizedData.RawValue -f $($currentValue -join ',') )
    
        if ( $options.keys -eq 'String' )
        {
            $stringValue = ( $currentValue -split ',' )[-1]
            $resultValue = ( $stringValue -replace '"' ).Trim()
        }
        else
        {
            Write-Verbose "Retrieving value for $valueName"
            if ( $currentSecurityPolicy.$section.keys -contains $valueName )
            {
                $resultValue = ( $accountPolicyData.$accountPolicy.Option.GetEnumerator() | 
                    Where-Object -Property Value -eq $currentValue.Trim() ).Name             
            }
            else
            {
                $resultValue = $null
            }
        }        
        $returnValue.Add( $accountPolicy, $resultValue )    
    }
    return $returnValue
}


function Set-TargetResource
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUserNameAndPassWordParams", "")]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [System.UInt32]
        $Enforce_password_history,

        [System.UInt32]
        $Maximum_Password_Age,

        [System.UInt32]
        $Minimum_Password_Age,

        [System.UInt32]
        $Minimum_Password_Length,

        [ValidateSet("Enabled","Disabled")]
        [System.String]
        $Password_must_meet_complexity_requirements,

        [ValidateSet("Enabled","Disabled")]
        [System.String]
        $Store_passwords_using_reversible_encryption,

        [System.UInt32]
        $Account_lockout_duration,

        [System.UInt32]
        $Account_lockout_threshold,

        [System.UInt32]
        $Reset_account_lockout_counter_after,

        [ValidateSet("Enabled","Disabled")]
        [System.String]
        $Enfore_user_logon_restrictions,

        [System.UInt32]
        $Maximum_lifetime_for_service_ticket,

        [System.UInt32]
        $Maximum_lifetime_for_user_ticket,

        [System.UInt32]
        $Maximum_lifetime_for_user_ticket_renewal,

        [System.UInt32]
        $Maximum_tolerance_for_computer_clock_synchronization
    )

    $kerberosPolicies = @()
    $systemAccessPolicies = @()
    $nonComplaintPolicies = @()
    $accountPolicyList = Get-PolicyOptionList -ModuleName MSFT_AccountPolicy
    $accountPolicyData = Get-PolicyOptionData -FilePath $("$PSScriptRoot\AccountPolicyData.psd1").Normalize()
    $script:seceditOutput = "$env:TEMP\Secedit-OutPut.txt"
    $accountPolicyToAddInf = "$env:TEMP\accountPolicyToAdd.inf"

    $desiredPolicies = $PSBoundParameters.GetEnumerator() | Where-Object -FilterScript { $PSItem.key -in $accountPolicyList }

    foreach ( $policy in $desiredPolicies )
    {
        $testParameters = @{
            Name = 'Test'
            $policy.Key = $policy.Value
            Verbose = $false
        }

        # define what policies are not in a desired state so we only add those policies
        # that need to be changed to the INF
        $isInDesiredState = Test-TargetResource @testParameters
        if ( -not ( $isInDesiredState ) )
        {
            $policyKey = $policy.Key
            $policyData = $securityOptionData.$policyKey
            $nonComplaintPolicies += $policyKey

            if ( $policyData.Option.GetEnumerator().Name -eq 'String' )
            {
                if ( [String]::IsNullOrWhiteSpace( $policyData.Option.String ) )
                {
                    $newValue = $policy.value                    
                }
                else
                {
                    $newValue = "$($policyData.Option.String)" + "$($policy.Value)"
                }
            }
            else
            {
                $newValue = $($policyData.Option[$policy.value])
            }

            if ( $policyData.Section -eq 'System Access' )
            {
                $systemAccessPolicies += "$($policyData.Value)=$newValue"
            }
            else
            {
                $kerberosPolicies += "$($policyData.Value)=$newValue"
            }
        }
    }

}


function Test-TargetResource
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingUserNameAndPassWordParams", "")]
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [System.UInt32]
        $Enforce_password_history,

        [System.UInt32]
        $Maximum_Password_Age,

        [System.UInt32]
        $Minimum_Password_Age,

        [System.UInt32]
        $Minimum_Password_Length,

        [ValidateSet("Enabled","Disabled")]
        [System.String]
        $Password_must_meet_complexity_requirements,

        [ValidateSet("Enabled","Disabled")]
        [System.String]
        $Store_passwords_using_reversible_encryption,

        [System.UInt32]
        $Account_lockout_duration,

        [System.UInt32]
        $Account_lockout_threshold,

        [System.UInt32]
        $Reset_account_lockout_counter_after,

        [ValidateSet("Enabled","Disabled")]
        [System.String]
        $Enfore_user_logon_restrictions,

        [System.UInt32]
        $Maximum_lifetime_for_service_ticket,

        [System.UInt32]
        $Maximum_lifetime_for_user_ticket,

        [System.UInt32]
        $Maximum_lifetime_for_user_ticket_renewal,

        [System.UInt32]
        $Maximum_tolerance_for_computer_clock_synchronization
    )

    #Write-Verbose "Use this cmdlet to deliver information about command processing."

    #Write-Debug "Use this cmdlet to write debug information while troubleshooting."


    <#
    $result = [System.Boolean]
    
    $result
    #>
}


Export-ModuleMember -Function *-TargetResource

