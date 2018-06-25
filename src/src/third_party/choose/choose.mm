//
//  choose.mm
//  choose
//
//  Created by BlueCocoa on 15/7/4.
//  Copyright (c) 2015 0xBBC. All rights reserved.
//

// 您必须了解:
/* GNU General Public License, Version 3 {{{ */
/* GPL协议 */
#warning 无论软件以何种形式发布，都必须同时附上源代码。例如在 Web 上提供下载，就必须在二进制版本（如果有的话）下载的同一个页面，清楚地提供源代码下载的链接。如果以光盘形式发布，就必须同时附上源文件的光盘。
#warning 开发或维护遵循 GPL 协议开发的软件的公司或个人，可以对使用者收取一定的服务费用。但还是一句老话——必须无偿提供软件的完整源代码，不得将源代码与服务做捆绑或任何变相捆绑销售。
#warning 你可以去掉所有原作的版权 信息，只要你保持开源，并且随源代码、二进制版附上 GPL 的许可证就行，让后人可以很明确地得知此软件的授权信息。GPL 精髓就是，只要使软件在完整开源 的情况下，尽可能使使用者得到自由发挥的空间，使软件得到更快更好的发展。
/* }}} */
// http://www.oschina.net/question/12_2826

/* Cycript - Optimizing JavaScript Compiler/Runtime
 * Copyright (C) 2009-2013  Jay Freeman (saurik)
 */

/* GNU General Public License, Version 3 {{{ */
/*
 * Cycript is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published
 * by the Free Software Foundation, either version 3 of the License,
 * or (at your option) any later version.
 *
 * Cycript is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Cycript.  If not, see <http://www.gnu.org/licenses/>.
 **/
/* }}} */

#import "choose.h"

#include <objc/runtime.h>
#include <malloc/malloc.h>
#include <mach/mach.h>
#include <set>

struct choice {
    std::set<Class> query_;
    std::set<id> result_;
};

struct ObjectStruct {
    Class isa_;
};

static kern_return_t read_memory(task_t task, vm_address_t address, vm_size_t size, void **data) {
    *data = reinterpret_cast<void *>(address);
    return KERN_SUCCESS;
}

static Class * copy_class_list(size_t &size) {
    size = objc_getClassList(NULL, 0);
    Class * data = reinterpret_cast<Class *>(malloc(sizeof(Class) * size));
    
    for (;;) {
        size_t writ = objc_getClassList(data, (int)size);
        if (writ <= size) {
            size = writ;
            return data;
        }

        Class * copy = reinterpret_cast<Class *>(realloc(data, sizeof(Class) * writ));
        if (copy == NULL) {
            free(data);
            return NULL;
        }
        data = copy;
        size = writ;
    }
}

static void choose_(task_t task, void *baton, unsigned type, vm_range_t *ranges, unsigned count) {
    choice * choice = reinterpret_cast<struct choice *>(baton);
    for (unsigned i = 0; i < count; ++i) {
        vm_range_t &range = ranges[i];
        void * data = reinterpret_cast<void *>(range.address);
        size_t size = range.size;
        
        if (size < sizeof(ObjectStruct))
            continue;
        
        uintptr_t * pointers = reinterpret_cast<uintptr_t *>(data);
#ifdef __arm64__
        Class isa = reinterpret_cast<Class>(pointers[0] & 0x1fffffff8);
#else
        Class isa = reinterpret_cast<Class>(pointers[0]);
#endif
        std::set<Class>::const_iterator result(choice->query_.find(isa));
        if (result == choice->query_.end())
            continue;
        
        size_t needed = class_getInstanceSize(*result);
        size_t boundary = 496;
#ifdef __LP64__
        boundary *= 2;
#endif
        if ((needed <= boundary && (needed + 15) / 16 * 16 != size) || (needed > boundary && (needed + 511) / 512 * 512 != size))
            continue;
        choice->result_.insert(reinterpret_cast<id>(data));
    }
}

@implementation my_choose

+ (NSArray *)my_choose:(NSString *)className{
    vm_address_t * zones = NULL;
    unsigned size = 0;
    kern_return_t error = malloc_get_all_zones(0, &read_memory, &zones, &size);
    assert(error == KERN_SUCCESS);
    
    size_t number;
    Class * classes = copy_class_list(number);
    assert(classes != NULL);
    
    choice choice;
    Class _class = NSClassFromString(className);
    
    for (size_t i = 0; i != number; ++i) {
        for (Class current = classes[i]; current != Nil; current = class_getSuperclass(current)) {
            if (current == _class) {
                choice.query_.insert(classes[i]);
                break;
            }
        }
    }
    free(classes);
    
    for (unsigned i = 0; i != size; ++i) {
        const malloc_zone_t * zone = reinterpret_cast<const malloc_zone_t *>(zones[i]);
        if (zone == NULL || zone->introspect == NULL)
            continue;
        zone->introspect->enumerator(mach_task_self(), &choice, MALLOC_PTR_IN_USE_RANGE_TYPE, zones[i], &read_memory, &choose_);
    }
    
#if __has_feature(objc_arc)
    NSMutableArray * result = [[NSMutableArray alloc] init];
#else
    NSMutableArray * result = [[[NSMutableArray alloc] init] autorelease];
#endif
    for (auto iter = choice.result_.begin(); iter != choice.result_.end(); iter++) {
        [result addObject:(id)*iter];
    }
    return result;
}

@end
