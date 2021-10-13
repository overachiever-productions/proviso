﻿Set-StrictMode -Version 1.0;


#region vNEXT
# vNEXT: It MAY (or may not) make sense to allow MULTIPLE Expects. 
# 		for example, TargetDomain ... could be "" or "WORKGROUP". Both answers are acceptable. 
# 	there are 2x main problems with this proposition, of course: 
#		1. How do I end up tweaking the .config to allow 1 or MORE values? (guess I could make arrays? e.g., instead of TargetDomain = "scalar" it could be TargetDomain = @("", "WORKGROUP")
# 		2. I then have to address how to compare one return value against multiple options. 
# 			that's easy on the surface - but a bit harder under the covers... 
# 				specifically:
# 					- does 1 match of actual vs ALL possibles yield a .Matched = true? 
# 					or does .Matched = true require that ALL values were matches? ... 
# 				i.e., this starts to get messy/ugly. 
# 		3. Yeah... the third out of 2 problems is ... that this tends to overly complicate things... it could spiral out of control quickly.
#endregion
function Expect {
	param (
		[ScriptBlock]$ExpectBlock
	);
	
	Limit-ValidProvisoDSL -MethodName "Expect" -AsFacet;
	$definition.AddExpect($ExpectBlock);
}