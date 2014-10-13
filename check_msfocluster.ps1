#!powershell.exe
 
# process Parameters
[CmdletBinding()]
Param(
        [Parameter(Mandatory=$False, HelpMessage="be verbose")]
        [switch]$veryverbose,
        [Parameter(Mandatory=$False)]
        [switch]$help,
        [Parameter(Mandatory=$False)]
        [switch]$perf,
        [Parameter(Mandatory=$False, HelpMessage="enter the disk warning threshold in % space left")]
        [double]$diskWarn,
        [Parameter(Mandatory=$False, HelpMessage="enter the disk warning threshold in % space left")]
        [double]$diskCrit,
        [Parameter(Mandatory=$False, HelpMessage="enter the names of ResourceGroups to exclude sep. by ," )]
        [string]$excludeRG,
        [Parameter(Mandatory=$False, HelpMessage="enter the names of ResourceGroups to exclude sep. by ," )]
        [string]$altTH
)
 
if ($help) {
        write-host "check_msfocluster is designed to check microsoft failovercluster"
        write-host " It checks if a clusternode or a ResourceGroup is down and"
        write-host " if there's enough disk space left"
        write-host "  -help        - get this help"
        write-host "  -perf        - add performance data output"
        write-host "  -veryVerbose - add some debug informations to your output"
        write-host "  -excludeRG <string> - exclude ResourceGroups (sep. by ,)"
        write-host "                      - exclude multiple Groups by writing `"group1|group2`""
        write-host "  -altTH <string>     - alternative threshold `"group,warn,crit`""
        write-host "                      - example: `"group1,40,30.group2,45,35`""
        write-host "  -diskWarn <int>     - check disks, assigned to your cluster ,against the"
        write-host "                        disk warning threshold in % space left"
        write-host "  -diskCrit <int>     - check disks, assigned to your cluster ,against the"
        write-host "                        disk critical threshold in % space left"
        write-host "`r`nExample: /check_nrpe -H 192.168.67.21 -p 5666 -c check_ps -a `"scripts\check_msfocluster.ps1`" -diskwarn 40 -diskcrit 30 -perf"
        write-host "         warning if 40% space left, critical if 30% space left"
        exit 3
}
 
# .veryverbose
# switch for verbose output
$output_list = new-object 'System.Collections.Generic.List[string]'
$debug_list = new-object 'System.Collections.Generic.List[string]'
$perf_list = new-object 'System.Collections.Generic.List[string]'
$exit = 0
$exit_message = @{ 0 = "OK"; 1 = "Warning"; 2 = "Critical"; 3 = "Unknown"}
$ResourceGroup_State = @{ -1 = "unknown"; 0 = "online"; 1 = "offline"; 2 = "failed"; 3 = "partial online"; 4 = "pending"}
$Node_State = @{ 0 = "up"; 1 = "down"; 2 = "paused"; 3 = "joining"}
if ($altTH) {
        if ($altTH -match "\.") {
                $altTHlist=@($altTH.split("\.")|% { $_.trim() })
        } else {
                $altTHlist=$altTH
        }
}
 
# get WMI Informations
$MSCluster_Node = @(Get-WmiObject -EnableAllPrivileges -query "select Name,State from MSCluster_Node where state!=0" -namespace "root\MSCluster")
#MSCluster_DiskPartition
$MSCluster_DiskPartition = @(Get-WmiObject -EnableAllPrivileges -query "select Path,FreeSpace,TotalSize from MSCluster_DiskPartition" -namespace "root\MSCluster")
#MSCluster_ResourceGroup
$MSCluster_ResourceGroup = @(Get-WmiObject -EnableAllPrivileges -query "select Name, state from MSCluster_ResourceGroup where PersistentState=true" -namespace "root\MSCluster")
#MSCluster_ResourceGroupToResource
$MSCluster_ResourceGroupToResource = @(Get-WmiObject -EnableAllPrivileges -query "select * from MSCluster_ResourceGroupToResource" -namespace "root\MSCluster")
#MSCluster_ResourceToDisk
$MSCluster_ResourceToDisk = @(Get-WmiObject -EnableAllPrivileges -query "select * from MSCluster_ResourceToDisk" -namespace "root\MSCluster")
#MSCluster_DiskToDiskPartition
$MSCluster_DiskToDiskPartition = @(Get-WmiObject -EnableAllPrivileges -query "select * from MSCluster_DiskToDiskPartition" -namespace "root\MSCluster")
 
# Allwissendes Disk Array $disks
$disks = @()
foreach ($i in $MSCluster_DiskToDiskPartition) {
        foreach ($j in $MSCluster_ResourceToDisk) {
                if($i.GroupComponent -eq $j.PartComponent) {
                        foreach ($k in $MSCluster_ResourceGroupToResource) {
                                if ($k.PartComponent -eq $j.GroupComponent) {
                                        $i.GroupComponent = $i.GroupComponent|select-string -pattern "`".*`""| % { $_.matches } | % { $_.value}
                                        $disk = new-object System.Object
										#echo $i.GroupComponent
                                        $disk | Add-Member –MemberType NoteProperty –Name ID –Value $i.GroupComponent
                                        $i.PartComponent = $i.PartComponent|select-string -pattern "`".*`""| % { $_.matches } | % { $_.value}
                                        $disk | Add-Member –MemberType NoteProperty –Name Path –Value $i.PartComponent
                                        $k.GroupComponent = $k.GroupComponent|select-string -pattern "`".*`""| % { $_.matches } | % { $_.value}
                                        $disk | Add-Member –MemberType NoteProperty –Name GroupName –Value $k.GroupComponent
                                        $j.GroupComponent = $j.GroupComponent|select-string -pattern "`".*`""| % { $_.matches } | % { $_.value}
										
                                        $disk | Add-Member –MemberType NoteProperty –Name DiskName –Value `"$j.GroupComponent`"
                                        $disk | Add-Member –MemberType NoteProperty –Name diskWarn –Value $diskWarn
                                        $disk | Add-Member –MemberType NoteProperty –Name diskCrit –Value $diskCrit
                                        #echo $disk.DiskName
										if ($altTHlist) {
                                                foreach ($row in $altTHlist) {
                                                        if ($veryverbose) {write-host -b green $row}
                                                        $thset=@($row.split(",")|% { $_.trim() })
                                                        if ($k.GroupComponent -match $thset[0]) {
                                                                $disk.diskWarn = $thset[1]
                                                                $disk.diskCrit = $thset[2]
                                                        }
                                                }
                                        }
                                        if ($excludeRG) {
                                                if ($disk.GroupName -match $excludeRG) {
                                                } else {
                                                $disks += $disk
                                                }
                                        } else {
                                            $disks += $disk
                                            }
                                }
                        }
                }
        }
}

if ( $veryverbose ) {
        foreach ($i in $disks) {
                $i.path
        }
        $disks
        $disks.count
}
 
# logical handling of these informations
# Are all nodes online? Is the Service running?
foreach ($i in $MSCLuster_Node) {
        if ($i) {
                $output_list.add(@("Node:", $i.name, "is", $Node_State.Get_Item([int]$i.state)))
                if ($exit -lt 1) { $exit = 1 }
        }
}
# Are all Resourcegroups in their desired state?
foreach ($i in $MSCLuster_ResourceGroup) {
        if ($i.name -match $excludeRG) {
        } else {
                if ($i.state -ne 0) {
                        $output_list.add(@("RGroup:", $i.name, "is", $ResourceGroup_State.Get_Item([int]$i.state)))
                        if ($exit -lt 2) { $exit = 2 }
                } else {
                        $output_list.add(@("RGroup:", $i.name, "is", $ResourceGroup_State.Get_Item([int]$i.state)))
                }
        }
}
# Is enough disk space left?
foreach ($i in $MSCluster_DiskPartition) {
        foreach ($j in $disks) {
                if ( $j.path -match $i.path) {
                        $freeP =  $(([decimal]$i.FreeSpace)/([decimal]$i.TotalSize)*100)
                        if ($freeP -lt $j.diskCrit) {
                                if ($exit -lt 2) { $exit = 2}
                                $output_list.add(@("DiskCrit:",$i.path, "of", $j.GroupName, "has", $freeP.ToString("0.0",$CultureDE)+"% left"))
                        } elseif ($freeP -lt $j.diskWarn) {
                                if ($exit -lt 1) { $exit = 1 }
                                $output_list.add(@("DiskWarn:",$i.path, "of", $j.GroupName, "has", $freeP.ToString("0.0",$CultureDE)+"% left"))
                        }
                        if ($veryverbose) {$debug_list.add(@("On", $i.path, "are", $i.FreeSpace, "MB left, that`'s", $freeP.ToString("0.0",$CultureDE)+"%"))}
						$perfItemName = $j.GroupName -replace " ", "_"
                        if ($perf) {$perf_list.add(@("DiskFree_"+$perfItemName+"_"+$i.path+"="+$i.FreeSpace+"MB;"+($i.TotalSize*$j.diskWarn/100)+";"+($i.TotalSize*$j.diskCrit/100)+" "))}
                }
        }
}
 
foreach ($i in $MSCluster_ResourceGroupToResource) {
}
 
foreach ($i in $MSCluster_ResourceGroupToResource) {
        if ($veryverbose) {$debug_list.add(@("RGR", $i ))}
}
 
foreach ($i in $MSCluster_DiskToDiskPartition) {
        if ($veryverbose) {$debug_list.add(@("DTDP", $i ))}
}
 
# Verbose
if ($veryverbose) {
        foreach ($i in $debug_list) {
                write-host $i
        }
        write-host -b blue "END VERBOSE"
}
 
# write text and returncode
# Write global state
write-host -NoNewline $exit_message.Get_Item($exit)
write-host -NoNewline ": "
 
# Write output
foreach ($i in $output_list) {
        write-host -noNewLine $i", "
        $back=1
}
if ($back) { if ($back -eq 1) {write-host -NoNewLine "`b`b "} }
 
if ($perf -AND ($diskWarn -OR $diskCrit)) {
        write-host -NoNewLine "`b|"
        foreach ($i in $perf_list) {
                #write-host "l"
                write-host -NoNewLine $i
        }
}
write-host
exit $exit
