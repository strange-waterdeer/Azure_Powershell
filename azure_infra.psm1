# Function to create a resource group
function New-KimkiResourceGroup {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$Location
    )

    Write-Host "`nCreating Resource Group" -ForegroundColor Yellow
    $rg = @{
        Name = $Name
        Location = $Location
    }
    New-AzResourceGroup @rg | Out-Null
    Write-Host "Resource Group Created" -ForegroundColor Yellow
}

# Function to create a virtual network
function New-KimkiVirtualNetwork {
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

    Write-Host "`nCreating Virtual Network" -ForegroundColor Yellow
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
function Add-KimkiSubnets {
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
function New-KimkiPublicIpAddress {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [array]$PublicIpConfigurations
    )

    Write-Host "`nCreating Public IP" -ForegroundColor Yellow
    
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
function New-KimkiNetworkSecurityGroups {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$NsgConfigurations
    )

    Write-Host "`nCreating Network Security Groups" -ForegroundColor Yellow
    
    $nsgObjects = @{}
    
    foreach ($nsgName in $NsgConfigurations.Keys) {
        $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $nsgName
        
        foreach ($rule in $NsgConfigurations[$nsgName]) {
            Add-AzNetworkSecurityRuleConfig @rule -NetworkSecurityGroup $nsg
        }
        
        $nsg | Set-AzNetworkSecurityGroup
        $nsgObjects[$nsgName] = $nsg
    }
    
    Write-Host "Network Security Groups Created" -ForegroundColor Yellow
    return $nsgObjects
}

# Function to create a Bastion service
function New-KimkiBastionService {
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
function New-KimkiVirtualMachines {
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

# Export all functions
Export-ModuleMember -Function New-KimkiResourceGroup, New-KimkiVirtualNetwork, Add-KimkiSubnets, New-KimkiPublicIpAddress, New-KimkiNetworkSecurityGroups, New-KimkiBastionService, New-KimkiVirtualMachines
