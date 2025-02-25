# AzureModule.psm1

#region 기본 리소스 생성 함수

# Function to create a resource group
function ResourceGroup {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$Location
    )

    Write-Host "`nCreateing Resource Group" -ForegroundColor Yellow
    $rg = @{
        Name = $Name
        Location = $Location
    }
    New-AzResourceGroup @rg | Out-Null
    Write-Host "Resource Group Created" -ForegroundColor Yellow
}

# Function to create a virtual network
function VirtualNetwork {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [string]$AddressPrefix
    )

    Write-Host "`nCreateing Virtual Network" -ForegroundColor Yellow
    $vnet = @{
        Name = $Name
        ResourceGroupName = $ResourceGroupName
        Location = $Location
        AddressPrefix = $AddressPrefix
    }
    $virtualNetwork = New-AzVirtualNetwork @vnet
    Write-Host "Virtual Network Created" -ForegroundColor Yellow
    
    return $virtualNetwork
}

# Function to add subnets to a virtual network
function Subnets {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork]$VirtualNetwork,
        
        [Parameter(Mandatory = $true)]
        [array]$SubnetConfigurations
    )

    Write-Host "`nCreating Subnets" -ForegroundColor Yellow
    
    foreach ($subnet in $SubnetConfigurations) {
        $subnetConfig = @{
            Name = $subnet.Name
            VirtualNetwork = $VirtualNetwork
            AddressPrefix = $subnet.AddressPrefix
        }
        Add-AzVirtualNetworkSubnetConfig @subnetConfig | Out-Null
    }

    $VirtualNetwork | Set-AzVirtualNetwork
    Write-Host "Created Subnets and added to Virtual Network" -ForegroundColor Yellow
}

# Function to create public IP addresses
function PublicIpAddress {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [array]$PublicIpConfigurations
    )

    Write-Host "`nCreateing Public IP" -ForegroundColor Yellow
    
    foreach ($publicIp in $PublicIpConfigurations) {
        $ipConfig = @{
            ResourceGroupName = $ResourceGroupName
            Name = $publicIp.Name
            Location = $Location
            AllocationMethod = $publicIp.AllocationMethod
            Sku = $publicIp.Sku
        }
        New-AzPublicIpAddress @ipConfig
    }
    
    Write-Host "Public IP Created" -ForegroundColor Yellow
}

# Function to create network security groups and rules
function NetworkSecurityGroups {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$NsgConfigurations
    )

    Write-Host "`nCreating Network Security Group" -ForegroundColor Yellow
    
    $nsgObjects = @{}
    
    foreach ($nsgName in $NsgConfigurations.Keys) {
        $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $nsgName
        
        foreach ($rule in $NsgConfigurations[$nsgName]) {
            Add-AzNetworkSecurityRuleConfig @rule -NetworkSecurityGroup $nsg
        }
        
        $nsg | Set-AzNetworkSecurityGroup
        $nsgObjects[$nsgName] = $nsg
    }
    
    Write-Host "Network Security Group Created" -ForegroundColor Yellow
    return $nsgObjects
}

# Function to create a Bastion service
function BastionService {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$PublicIpAddressName,
        
        [Parameter(Mandatory = $true)]
        [string]$VirtualNetworkName,
        
        [Parameter(Mandatory = $true)]
        [string]$Sku
    )

    Write-Host "`nCreating Bastion Service" -ForegroundColor Yellow
    $bastion = @{
        Name = $Name
        ResourceGroupName = $ResourceGroupName
        PublicIpAddressRgName = $ResourceGroupName
        PublicIpAddressName = $PublicIpAddressName
        VirtualNetworkRgName = $ResourceGroupName
        VirtualNetworkName = $VirtualNetworkName
        Sku = $Sku
    }
    New-AzBastion @bastion
    Write-Host "Bastion Service Created" -ForegroundColor Yellow
}

# Function to create virtual machines
function VirtualMachines {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [string]$VirtualNetworkName,
        
        [Parameter(Mandatory = $true)]
        [string]$VMSize,
        
        [Parameter(Mandatory = $true)]
        [string]$OSDiskSku,
        
        [Parameter(Mandatory = $true)]
        [string]$VMUsername,
        
        [Parameter(Mandatory = $true)]
        [securestring]$VMPassword,
        
        [Parameter(Mandatory = $true)]
        [array]$VMConfigurations,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$NsgMapping
    )

    Write-Host "`nCreating Virtual Machines" -ForegroundColor Yellow
    
    $VMCredential = New-Object System.Management.Automation.PSCredential ($VMUsername, $VMPassword)
    
    foreach ($vmConfig in $VMConfigurations) {
        $nicName = "$($vmConfig.Name)-nic"
        $subnetId = (Get-AzVirtualNetwork -Name $VirtualNetworkName -ResourceGroupName $ResourceGroupName).Subnets.Where({$_.Name -eq $vmConfig.SubnetName}).Id
        
        $nsgName = $NsgMapping[$vmConfig.SubnetName]
        $nsg = Get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName
        
        $nic = New-AzNetworkInterface -Name $nicName `
            -ResourceGroupName $ResourceGroupName `
            -Location $Location `
            -SubnetId $subnetId `
            -NetworkSecurityGroupId $nsg.Id `
            -PrivateIpAddress $vmConfig.PrivateIpAddress

        $vmName = $vmConfig.Name
        $vm = New-AzVMConfig -VMName $vmName -VMSize $VMSize

        $vm = Set-AzVMOperatingSystem -VM $vm `
            -Linux `
            -ComputerName $vmName `
            -Credential $VMCredential `
            -CustomData $vmConfig.CustomData

        $vm = Set-AzVMOSDisk -VM $vm `
            -CreateOption FromImage `
            -StorageAccountType $OSDiskSku

        $vm = Set-AzVMSourceImage -VM $vm `
            -PublisherName 'Canonical' `
            -Offer '0001-com-ubuntu-server-jammy' `
            -Skus '22_04-lts' `
            -Version 'latest'

        $vm = Add-AzVMNetworkInterface -VM $vm -Id $nic.Id
        $vm = Set-AzVMBootDiagnostic -VM $vm -Disable

        Write-Host "Creating VM: $vmName" -ForegroundColor Yellow
        New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vm
        Write-Host "VM Created: $vmName" -ForegroundColor Yellow
    }

    Write-Host "All Virtual Machines Created" -ForegroundColor Yellow
}

#endregion

#region 배포 함수

# Function to initialize the deployment and load configuration
function Initialize {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigFilePath,
        
        [Parameter(Mandatory = $false)]
        [string]$CustomDataBasePath = ".\CustomData"
    )
    
    # Load configuration from JSON file
    $config = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
    
    # Create CustomData directory if it doesn't exist
    if (-not (Test-Path $CustomDataBasePath)) {
        New-Item -ItemType Directory -Path $CustomDataBasePath -Force | Out-Null
    }
    
    # Return the configuration
    return $config
}

# Function to deploy Resource Group
function CreateResourceGroup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    ResourceGroup -Name $Config.ResourceGroup.Name -Location $Config.ResourceGroup.Location
    
    return $Config.ResourceGroup.Name
}

# Function to deploy Virtual Network
function CreateVirtualNetwork {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )
    
    $vnet = VirtualNetwork -Name $Config.VirtualNetwork.Name `
                          -ResourceGroupName $ResourceGroupName `
                          -Location $Config.ResourceGroup.Location.ToLower() `
                          -AddressPrefix $Config.VirtualNetwork.AddressPrefix
    
    return $vnet
}

# Function to deploy Subnets
function CreateSubnets {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork]$VirtualNetwork
    )
    
    $subnets = @()
    foreach ($subnet in $Config.Subnets) {
        $subnets += @{
            Name = $subnet.Name
            AddressPrefix = $subnet.AddressPrefix
        }
    }
    Subnets -VirtualNetwork $VirtualNetwork -SubnetConfigurations $subnets
}

# Function to deploy Public IP Addresses
function CreatePublicIpAddresses {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )
    
    $publicIps = @()
    foreach ($publicIp in $Config.PublicIps) {
        $publicIps += @{
            Name = $publicIp.Name
            AllocationMethod = $publicIp.AllocationMethod
            Sku = $publicIp.Sku
        }
    }
    PublicIpAddress -ResourceGroupName $ResourceGroupName `
                    -Location $Config.ResourceGroup.Location.ToLower() `
                    -PublicIpConfigurations $publicIps
}

# Function to deploy Network Security Groups
function CreateNetworkSecurityGroups {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )
    
    $nsgConfigurations = @{}
    
    foreach ($nsgName in ($Config.NetworkSecurityGroups | Get-Member -MemberType NoteProperty).Name) {
        $nsgRules = @()
        foreach ($rule in $Config.NetworkSecurityGroups.$nsgName) {
            $nsgRules += @{
                Name = $rule.Name
                Protocol = $rule.Protocol
                SourcePortRange = $rule.SourcePortRange
                DestinationPortRange = $rule.DestinationPortRange
                SourceAddressPrefix = $rule.SourceAddressPrefix
                DestinationAddressPrefix = $rule.DestinationAddressPrefix
                Access = $rule.Access
                Priority = $rule.Priority
                Direction = $rule.Direction
            }
        }
        $nsgConfigurations[$nsgName] = $nsgRules
    }
    
    $nsgs = NetworkSecurityGroups -ResourceGroupName $ResourceGroupName `
                                  -Location $Config.ResourceGroup.Location.ToLower() `
                                  -NsgConfigurations $nsgConfigurations
    
    return $nsgs
}

# Function to deploy Bastion Service
function CreateBastionService {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )
    
    BastionService -Name $Config.BastionService.Name `
                  -ResourceGroupName $ResourceGroupName `
                  -PublicIpAddressName $Config.BastionService.PublicIpAddressName `
                  -VirtualNetworkName $Config.VirtualNetwork.Name `
                  -Sku $Config.BastionService.Sku
}

# Function to deploy Virtual Machines
function CreateVirtualMachines {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )
    
    # Set VM credentials
    $VMUsername = $Config.VirtualMachines.Credentials.Username
    $VMPassword = $Config.VirtualMachines.Credentials.Password | ConvertTo-SecureString -AsPlainText -Force
    
    # Create NsgMapping from configuration
    $nsgMapping = @{}
    foreach ($mapping in ($Config.VirtualMachines.NsgMapping | Get-Member -MemberType NoteProperty).Name) {
        $nsgMapping[$mapping] = $Config.VirtualMachines.NsgMapping.$mapping
    }
    
    # Create VM configurations from JSON
    $vmConfigs = @()
    foreach ($vm in $Config.VirtualMachines.Instances) {
        # Read CustomData from YAML file
        $customDataPath = Join-Path -Path (Get-Location) -ChildPath $vm.CustomDataPath
        $customData = Get-Content -Path $customDataPath -Raw
        
        $vmConfigs += @{
            Name = $vm.Name
            PrivateIpAddress = $vm.PrivateIpAddress
            SubnetName = $vm.SubnetName
            CustomData = $customData
        }
    }
    
    VirtualMachines -ResourceGroupName $ResourceGroupName `
                   -Location $Config.ResourceGroup.Location.ToLower() `
                   -VirtualNetworkName $Config.VirtualNetwork.Name `
                   -VMSize $Config.VirtualMachines.CommonSettings.VMSize `
                   -OSDiskSku $Config.VirtualMachines.CommonSettings.OSDiskSku `
                   -VMUsername $VMUsername `
                   -VMPassword $VMPassword `
                   -VMConfigurations $vmConfigs `
                   -NsgMapping $nsgMapping
}

# Main deployment orchestration function
function Deploy {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigFilePath,
        
        [Parameter(Mandatory = $false)]
        [string]$CustomDataBasePath = ".\CustomData"
    )
    
    # Initialize deployment
    $config = Initialize -ConfigFilePath $ConfigFilePath -CustomDataBasePath $CustomDataBasePath
    
    # Deploy Resource Group
    $resourceGroupName = CreateResourceGroup -Config $config
    
    # Deploy Virtual Network
    $vnet = CreateVirtualNetwork -Config $config -ResourceGroupName $resourceGroupName
    
    # Deploy Subnets
    CreateSubnets -Config $config -VirtualNetwork $vnet
    
    # Deploy Public IP Addresses
    CreatePublicIpAddresses -Config $config -ResourceGroupName $resourceGroupName
    
    # Deploy Network Security Groups
    CreateNetworkSecurityGroups -Config $config -ResourceGroupName $resourceGroupName
    
    # Deploy Bastion Service
    CreateBastionService -Config $config -ResourceGroupName $resourceGroupName
    
    # Deploy Virtual Machines
    CreateVirtualMachines -Config $config -ResourceGroupName $resourceGroupName
}

#endregion

# Export all functions
Export-ModuleMember -Function ResourceGroup, VirtualNetwork, Subnets, PublicIpAddress, NetworkSecurityGroups, BastionService, VirtualMachines, Initialize, CreateResourceGroup, CreateVirtualNetwork, CreateSubnets, CreatePublicIpAddresses, CreateNetworkSecurityGroups, CreateBastionService, CreateVirtualMachines, Deploy
