//
//  Logging.swift
//  Gladys
//
//  Created by Paul Tsochantaris on 09/02/2019.
//  Copyright © 2019 Paul Tsochantaris. All rights reserved.
//

#if DEBUG
import os.log
#endif

func log(_ line: @autoclosure ()->String) {
	#if DEBUG
	os_log("%{public}@", line())
	#endif
}
