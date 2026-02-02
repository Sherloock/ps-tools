BeforeAll {
    # Load the helpers module (contains Get-FlattenUniqueFileName)
    . "$PSScriptRoot\..\core\Helpers.ps1"
    # Load the files module
    . "$PSScriptRoot\..\core\Files.ps1"
}

Describe "Get-FlattenUniqueFileName" {
    BeforeAll {
        # Create a test directory structure
        $script:TestRoot = "$TestDrive\FlattenTest"
        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null
    }

    It "returns original filename when no conflict" {
        $result = Get-FlattenUniqueFileName -TargetFolder $script:TestRoot -FileName "newfile.txt"
        $result | Should -Be "newfile.txt"
    }

    It "appends counter when file exists" {
        # Create a conflicting file
        New-Item -Path "$($script:TestRoot)\existing.txt" -ItemType File -Force | Out-Null

        $result = Get-FlattenUniqueFileName -TargetFolder $script:TestRoot -FileName "existing.txt"
        $result | Should -Be "existing-1.txt"
    }

    It "increments counter for multiple conflicts" {
        # Create multiple conflicting files
        New-Item -Path "$($script:TestRoot)\multi.txt" -ItemType File -Force | Out-Null
        New-Item -Path "$($script:TestRoot)\multi-1.txt" -ItemType File -Force | Out-Null
        New-Item -Path "$($script:TestRoot)\multi-2.txt" -ItemType File -Force | Out-Null

        $result = Get-FlattenUniqueFileName -TargetFolder $script:TestRoot -FileName "multi.txt"
        $result | Should -Be "multi-3.txt"
    }

    It "preserves file extension" {
        New-Item -Path "$($script:TestRoot)\doc.pdf" -ItemType File -Force | Out-Null

        $result = Get-FlattenUniqueFileName -TargetFolder $script:TestRoot -FileName "doc.pdf"
        $result | Should -Be "doc-1.pdf"
    }

    It "handles files without extension" {
        New-Item -Path "$($script:TestRoot)\noext" -ItemType File -Force | Out-Null

        $result = Get-FlattenUniqueFileName -TargetFolder $script:TestRoot -FileName "noext"
        $result | Should -Be "noext-1"
    }
}

Describe "Flatten" {
    Context "Parameter validation" {
        It "returns early for non-existent folder" {
            $result = Flatten -RootFolder "$TestDrive\NonExistent" -OutputFolder "$TestDrive\NonExistent" -Copy -Force *>&1
            $result | Should -Match "does not exist"
        }

        It "returns early when no files to flatten" {
            $emptyRoot = "$TestDrive\EmptyRoot"
            New-Item -Path $emptyRoot -ItemType Directory -Force | Out-Null

            $result = Flatten -RootFolder $emptyRoot -OutputFolder $emptyRoot -Copy -Force *>&1
            $result | Should -Match "No files found"
        }
    }

    Context "Copy mode" {
        BeforeEach {
            # Setup test structure with unique names per test run
            $script:CopyRoot = "$TestDrive\CopyTest_$(Get-Random)"
            New-Item -Path "$script:CopyRoot\sub1" -ItemType Directory -Force | Out-Null
            New-Item -Path "$script:CopyRoot\sub2\deep" -ItemType Directory -Force | Out-Null

            "content1" | Set-Content "$script:CopyRoot\sub1\file1.txt"
            "content2" | Set-Content "$script:CopyRoot\sub2\file2.txt"
            "content3" | Set-Content "$script:CopyRoot\sub2\deep\file3.txt"
        }

        It "copies files to root folder" {
            Flatten -RootFolder $script:CopyRoot -OutputFolder $script:CopyRoot -Copy -Force *>$null

            # Original files should still exist
            Test-Path "$script:CopyRoot\sub1\file1.txt" | Should -Be $true
            Test-Path "$script:CopyRoot\sub2\file2.txt" | Should -Be $true
            Test-Path "$script:CopyRoot\sub2\deep\file3.txt" | Should -Be $true

            # Flattened files should exist in root
            Test-Path "$script:CopyRoot\file1.txt" | Should -Be $true
            Test-Path "$script:CopyRoot\file2.txt" | Should -Be $true
            Test-Path "$script:CopyRoot\file3.txt" | Should -Be $true
        }

        It "copies to separate output folder" {
            $outputFolder = "$TestDrive\CopyOutput_$(Get-Random)"
            New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null

            Flatten -RootFolder $script:CopyRoot -OutputFolder $outputFolder -Copy -Force *>$null

            # Files should be in output folder
            Test-Path "$outputFolder\file1.txt" | Should -Be $true
            Test-Path "$outputFolder\file2.txt" | Should -Be $true
            Test-Path "$outputFolder\file3.txt" | Should -Be $true
        }
    }

    Context "Move mode" {
        BeforeEach {
            # Setup test structure
            $script:MoveRoot = "$TestDrive\MoveTest_$(Get-Random)"
            New-Item -Path "$script:MoveRoot\sub1" -ItemType Directory -Force | Out-Null
            New-Item -Path "$script:MoveRoot\sub2" -ItemType Directory -Force | Out-Null

            "content1" | Set-Content "$script:MoveRoot\sub1\file1.txt"
            "content2" | Set-Content "$script:MoveRoot\sub2\file2.txt"
        }

        It "moves files and removes empty directories" {
            Flatten -RootFolder $script:MoveRoot -OutputFolder $script:MoveRoot -Move -Force *>$null

            # Files should be in root
            Test-Path "$script:MoveRoot\file1.txt" | Should -Be $true
            Test-Path "$script:MoveRoot\file2.txt" | Should -Be $true

            # Original locations should be empty/removed
            Test-Path "$script:MoveRoot\sub1\file1.txt" | Should -Be $false
            Test-Path "$script:MoveRoot\sub2\file2.txt" | Should -Be $false
        }
    }

    Context "Duplicate handling" {
        BeforeEach {
            $script:DupRoot = "$TestDrive\DupTest_$(Get-Random)"
            New-Item -Path "$script:DupRoot\sub1" -ItemType Directory -Force | Out-Null
            New-Item -Path "$script:DupRoot\sub2" -ItemType Directory -Force | Out-Null

            # Create files with same name in different subfolders
            "content1" | Set-Content "$script:DupRoot\sub1\same.txt"
            "content2" | Set-Content "$script:DupRoot\sub2\same.txt"
        }

        It "handles duplicate filenames by appending counter" {
            Flatten -RootFolder $script:DupRoot -OutputFolder $script:DupRoot -Copy -Force *>$null

            # Both files should exist with unique names
            Test-Path "$script:DupRoot\same.txt" | Should -Be $true
            Test-Path "$script:DupRoot\same-1.txt" | Should -Be $true

            # Content should be preserved
            $content1 = Get-Content "$script:DupRoot\same.txt"
            $content2 = Get-Content "$script:DupRoot\same-1.txt"

            ($content1 -eq "content1" -or $content1 -eq "content2") | Should -Be $true
            ($content2 -eq "content1" -or $content2 -eq "content2") | Should -Be $true
            $content1 | Should -Not -Be $content2
        }
    }
}
