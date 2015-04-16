Param($csv,[switch]$help) # Define parameters to expect.

import-module ActiveDirectory # Include a goldmine of cmdlets.

# VARIABLES/OBJECTS
$Class = "User" # Define type of object being added.
$dc = "dc=steal,dc=lan" # Define domain.
$ou = "ou=Students" # Define OU.
$exDate = get-date (get-date).AddDays(120) -uformat %D # Calc expiration.
# END VARIABLES/OBJECTS

function helper() # Help function.
{
$helpstr=@"

NAME
	UserAdd.ps1

SYNOPSIS
	Adds users to the STEAL domain and prepares a share folder.

SYNTAX
	UserAdd.ps1 -csv <csv path> [-help]
	
PARAMETERS
	-csv <csv path>
		Specifies the location of the csv file that contains the user list.
		The csv is organized by username,firstName,lastName,password.
	
	-help
		Prints this help.

VERSION
	This is version 0.3.
	
AUTHOR
	Charles Spence IV
	STEAL Lab Manager
	cspence@unomaha.edu
	April 16, 2015
	
"@
$helpstr # Display help
exit
}

function userExist($chkuser) # Checks if a username exists.
{
 $out = $false # Set default return value.
 
 $Search = New-Object System.DirectoryServices.DirectorySearcher
 $Search.SearchRoot = $("LDAP://"+$dc)
 $Search.Filter = ("(objectCategory=User)")
 $Results = $Search.FindAll() # Gather all user information.
 
 foreach ($Result in $Results) # Check for username.
 {
  if( $Result.Properties.samaccountname -eq $chkuser )
  {
   $out = $true
   break
  }
 }
 
 return $out
}

function userSFS($chkuser)
{
 $out = $false # Set default return value.
 
 $sfs = Get-ADGroupMember -Identity SFS # Gather all the members of SFS.
 
 foreach ($mem in $sfs)
 {
  if( $mem.samaccountname -eq $chkuser ) # SFS member?
  {
   $out = $true
   break
  } 
 }
  return $out
}

function createUser($username, $firstname, $lastname, $pword)
{
 New-ADUser -Name $($lastname+", "+$firstname) `
 -AccountExpirationDate $exDate `
 -AccountPassword $(ConvertTo-SecureString -AsPlainText -Force $pword) `
 -ChangePasswordAtLogon $true -DisplayName $($firstname+" "+$lastname) `
 -Enabled $true -GivenName $firstname -Path $($ou+","+$dc) `
 -SamAccountName $username -Surname $lastname `
 -UserPrincipalName $($username+"@steal.lan")
}

function setMod($tarDir, $username) # Sets ACL to Modify for user on $tarDir
{
 $fACL = Get-ACL $tarDir
 ## $fACL.SetAccessRuleProtection($True,$True) # Use for inheritance issues.
 $fRule = New-Object System.Security.AccessControl.FileSystemAccessRule `
 ($username,"Modify","ContainerInherit, ObjectInherit","None","Allow")
 $fACL.AddAccessRule($fRule)
 Set-ACL $tarDir $fACL # Apply
}

clear # Clear the screen.
if($help) { helper } # Check for help parameter.
if(!$csv) { echo "ERROR: No csv file provided!" ; exit }

$ulist = import-csv $csv -Header "uname","fname","lname","pword" # Fetch csv.

echo ""
echo "###############################################################"
echo ""
echo "                 Adding users to STEAL.LAN                     "
echo ""
echo "###############################################################"
echo ""

foreach($line in $ulist) # Add users one at a time.
{
 $samname = $line.uname # Save the username since it is used frequently.
 echo "=============================================================="
 echo ""
 " Checking if {0} already exists..." -f $samname
 $UserEx = userExist($samname) # Check if username exists
 
 if($UserEx) # If it does...
 {
  " Username {0} already exists." -f $samname
  if(!$(userSFS $samname)) # If they are not SFS.
  {
   set-ADAccountExpiration -Identity $samname -DateTime $exDate
   Enable-ADAccount -Identity $samname # Re-enable account.
   " The account for {0} will expire in 120 days." -f $samname
  }
  else
  {
   " No expiration applied to {0}. This is an SFS member." -f $samname
  }
 }
 else # If it doesn't...
 {
  " Creating account for {0}" -f $samname
  createUser $samname $($line.fname) $($line.lname) $($line.pword)
  " {0} {1} has been given the username {2}" `
  -f $($line.fname),$($line.lname),$($samname)
 }
 
 echo ""
 $shareDir = "U:\"+$samname # Define user folder.
 
 if(test-path -path $shareDir -type container) # Check for STEALNAS directory.
 {
  if(!$UserEx) # Warning for creating a new user with pre-existing directory.
  {
   echo " WARNING: Pre-existing folder with this name!"
  }
  else
  {
   echo " Share exists for this user."
  }
 }
 else # No share exists...
 {
  echo " Share does not exist for this user."
  New-Item $shareDir -Type Directory | out-null # Create directory silently.
  " Created {0}" -f $shareDir
 }

 setMod $shareDir $samname # Set Modify permissions on share folder.
 " Permissions added to {0} for {1}" -f $shareDir,$samname
 echo ""
 echo "=============================================================="
 echo ""
}

echo "###############################################################"
echo ""
echo "                  UserAdd script completed                    "
echo ""
echo "###############################################################"
echo ""