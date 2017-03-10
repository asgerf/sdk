// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
part of kernel.laboratory;

// This part file contains bindings to the HTML file, possibly wrapped in a
// higher-level view object.

FileUploadInputElement reportFileInput =
    document.getElementById('report-file-input');

FileUploadInputElement kernelFileInput =
    document.getElementById('kernel-file-input');

ButtonElement reloadButton = document.getElementById('reload-button');

DivElement debugBox = document.getElementById('debug-box');

CodeView codeView = new CodeView(document.getElementById('code-view'));
