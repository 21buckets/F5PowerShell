
function Convert-InputURLCategoriesToHash {

    Param(
        [string[]][Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
        $urlCategories,


        [String][Parameter(Mandatory = $false)]
        $categoryPrefix,

        [switch]$convertToJSON
    )


    $categories_object = @{}


    #Basic validation of first line of file to make sure it meets formatting requirements.
    if(-not($urlCategories[0].StartsWith("define category"))){
        throw "File does not meet expected file format. Data should look like: `
        `define category `"{{categoryName}}`" `
        {{url1}} `
        ... `
        {{urlN}} `
        end"
    }


    foreach($line in $urlCategories){

        if($line.StartsWith("define category")){
           
            $matches = ([regex] 'define category "(.+)"').matches($line)
            $category = $matches[0].Groups[1].Value
            $urls = @()
        }elseif($line.StartsWith("end")){
            if($categoryPrefix){
                $category_with_prefix = "$categoryPrefix$category"
                $categories_object[$category_with_prefix] = $urls
            }else{
                $categories_object[$category] = $urls
            }
        }else{
            $url = [PSCustomObject]@{
                name =  $line
                type = "glob-match"
            }
            $urls += $url 

            

        }

    }



    if($convertToJSON){
        return $categories_object | Convertto-json -Depth 100
    }else{
        return $categories_object
    }


}
function Convert-F5UrlCategoriesToHash {
    Param(
        [Object[]][Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
        $f5_url_categories
    )


    $category_object = @{}
    foreach($category in $f5_url_categories){
        $f5_urls = $category.urls
        $category_object[$($category.name)] = $category.urls
        


    }

    $category_object

}
function Set-F5UrlCategoryChanges {

    Param(
        [String][Parameter(Mandatory = $false, ParameterSetName = "path")][ValidateNotNullOrEmpty()]
        $url_category_content_path,

        [Object[]][Parameter(Mandatory = $false, ParameterSetName = "content")][ValidateNotNullOrEmpty()]
        $url_category_content,

        [string][Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()]
        $f5_connection,

        [Switch]$allow_deletion_urls,
        [Switch]$allow_deletion_categories,
        [String][Parameter(Mandatory = $false)][ValidateNotNullOrEmpty()]
        $prefix_category_name,

        [Switch]$debug_logging
       
    )



    <#
        .SYNOPSIS
        Adds or removes URLs and categories to the F5 Access URL Category section based on comparison to an input file.

        .DESCRIPTION
        Adds or removes URLs and categories to the F5 APM URL Category section based on comparison to an input file.
        Using the $prefix_category_name parameter, you can limit the comparison to categories matching the prefix. 
        This allows the requestor to automate the adding/removing of a specific type of category, while still permitting
        manual category management for the non-autmated categories.


        .PARAMETER url_category_content_path
        Provide the local file path to the new URL Category content. Use instead of 'url_category_content'

        .PARAMETER url_category_content
        Provide the URL Category content to be compared with the F5 categories. Use instead of 'url_category_content_path'

        .PARAMETER f5_connection
        Provides the connection to the relevant F5. If not provided, the default connection will be used

        .PARAMETER allow_deletion_urls
        Without this switch, the script will not delete any URLS

        .PARAMETER allow deletion_categories
        Without this switch, the script will not delete any categories

        .PARAMETER prefix_category_name
        Adds a prefix to the categories being added. When used, the comparison of the new file to the F5 will filter
        out any categories that do not contain this prefix. This allows for the automation of desired categories while
        still supporting manual creation and management of other categories.


    #>





    #Get the content from a local filepath
    if($url_category_content_path){
        $url_category_content = Get-Content -Path $url_category_content_path
        if($debug_logging){Write-Host "Retrieved content from $url_category_content_path"}
    }

    #Convert the content to a structured JSON format
    $new_url_categories_hash = Convert-InputURLCategoriesToHash -urlCategories $url_category_content -categoryPrefix $prefix_category_name

    #Get the content from the F, allowing a specific f5_connection, or using the default.
    if($f5_connection){
        $f5_custom_categories = get-F5UrlCategory -custom_only -f5_connection $f5_connection
    }else{
        if($debug_logging){Write-Host "Using the default F5 connection to retrieve SWG URL Categories"}
        $f5_custom_categories = get-F5UrlCategory -custom_only
    }

    #Convert the F5 response to same data structure as file content
    $f5_custom_categories_hash = Convert-F5UrlCategoriesToHash -f5_url_categories $f5_custom_categories
   # $f5_custom_categories_hash | convertto-json 


    <#
        Process is likely not the quickest, but is simple to follow:
        1. Compare the category names to see which are to be deleted entirely (Act on these first)

        2. Compare each URL in the new file, taking 1 of 3 actions:
           1. Add entire new category
           2. Add new URLs to existing category
           3. Remove URLs from existing category

    #>



    #Step 1: Comparing the category names to see which can be deleted entirely. (Added debug logging for each comparison for troubleshooting if required.
    $category_comparison = Compare-Object -ReferenceObject $($f5_custom_categories_hash.GetEnumerator().Name) -DifferenceObject $($new_url_categories_hash.getEnumerator().Name) -IncludeEqual
    foreach($cat_comp in $category_comparison){
        $category_name = $cat_comp.InputObject
        switch($($cat_comp.SideIndicator)){
            "==" {
                #Category exists in both locations
                if($debug_logging){Write-Host "[$category_name]  Category $($cat_comp.InputObject) exists in both locations and will be compared for URL differences"}
            }
            "=>"{
                # Category exists in the new file only (not on the F5)
                if($debug_logging){Write-Host "[$category_name]  Category $($cat_comp.InputObject) exists only in the differenceObject (new file) and will be added shortly."}
            }
            "<="{
                #Category does not exist in the new file, but does on the F5
                $to_delete = $false
                if($prefix_category_name -and ($($cat_comp.InputObject).startsWith($prefix_category_name))){
                    if($debug_logging){Write-Host "[$category_name]  Category $($cat_comp.InputObject) exists only on the ReferenceObject (F5) and matches the provided category prefix ($prefix_category_name), so will be deleted provided the allow_deletion_categories flag is set: ($allow_deletion_categories)"}
                    $to_delete = $true
                }elseif($prefix_category_name){
                    if($debug_logging){Write-Host "[$category_name]  Category $($cat_comp.InputObject) exists only on the ReferenceObject (F5) but there is a prefix provided which this category does not match, so the category wont be deleted."}
                }else{
                    if($debug_logging){Write-Host "[$category_name]  Category $($cat_comp.InputObject) exists only on the ReferenceObject (F5) and no category prefix has been provided, so will be deleted provided the allow_deletion_categories flag is set: ($allow_deletion_categories)"}
                    $to_delete = $true
                }

                if($to_delete -and $allow_deletion_categories){
                    Remove-F5UrlCategory -name $($cat_comp.InputObject)
                    if($debug_logging){Write-Host "[$category_name]  Category $($cat_comp.InputObject) has been deleted as it does not exist in the new URL file, and the allow_deletion_categories switch has been set"}
                }
            }
        }
    }




    #Step 2: Loop through each of the newly provided categories to see whether they need to be added, or URLS modified (added or deleted)

    #Write-Host "URL Categories to loop through: $($new_url_categories.keys)"
    foreach($category in $new_url_categories_hash.keys){
        if($debug_logging){Write-Host "[$category]  Checking status of category $category"}
        $new_urls = $new_url_categories_hash.$category

        #If the category doesnt exist at all, let's just add it!
        if(-not ($category -in $f5_custom_categories_hash.keys)){
            if($debug_logging){Write-Host "[$category]  Adding entire category $category as it does not exist on F5 at all"}
           
            $urls_tmsh_format = ''
            foreach($url in $new_urls){               
                if($debug_logging){Write-Host "[$category]  Adding URL: $($url.name) to category: $category"}
                $urls_tmsh_format = "$urls_tmsh_format $($url.name) { type $($url.type) }"
                
            }
            
            $bash_command = execute-F5BashCommand -command "-c `"tmsh create sys url-db url-category $category display-name $category urls add {$urls_tmsh_format}`""
            
            if($debug_logging){Write-Host "[$category]  Executed bash command $($bash_command.utilCmdArgs)"}
            
          

        }else{
            if($debug_logging){Write-Host "[$category]  Category $category exists on the F5. Checking new URLS"}


            $existing_urls = $f5_custom_categories_hash.$category

            #Compare the URLs on the F5 versus URLs in the input file to only return differences
            $comparison = Compare-Object -ReferenceObject $existing_urls -DifferenceObject $new_urls -Property Name -IncludeEqual

            $add_urls_tmsh_format = ''
            $delete_urls_tmsh_format = ''
            foreach($diff_url in $comparison){               
                #Only get differences where new URLs would be added to the F5 (i.e. don't try and remove any)
                if($($diff_url.sideIndicator -eq "=>")){
                    if($debug_loggign){Write-Host "[$category]  Adding URL: $($diff_url.name) to category: $category"}
                    $diff_object = $new_urls | Where-Object {$_.name -eq $($diff_url.name)}
                    $add_urls_tmsh_format = "$add_urls_tmsh_format $($diff_object.name) { type $($diff_object.type) }"
                }elseif($($diff_url.sideIndicator -eq "<=")){
                    if($debug_loggign){Write-Host "[$category]  Removing URL: $($diff_url.name) from category: $category if the allow_deletion_urls flag is set"}
                     $delete_urls_tmsh_format = "$delete_urls_tmsh_format $($diff_url.name)"

                }
            }
            if($add_urls_tmsh_format){
                $bash_command = execute-F5BashCommand -command "-c `"tmsh modify sys url-db url-category $category urls add {$add_urls_tmsh_format}`""
                if($debug_logging){Write-Host "[$category]  Executed bash command $($bash_command.utilCmdArgs)"}
            }

            if($delete_urls_tmsh_format){               
                if($allow_deletion_urls){
                     $bash_command = execute-F5BashCommand -command "-c `"tmsh modify sys url-db url-category $category urls delete {$delete_urls_tmsh_format}`""
                     if($debug_logging){Write-Host "[$category] Executed bash command $($bash_command.utilCmdArgs)"}
                }
                
                
            }
        }             
    }

}
