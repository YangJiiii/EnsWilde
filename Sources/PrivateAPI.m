//
//  PrivateAPI.m
//  EnsWilde
//
//  Created by Duy Tran on 12/12/25.
//

#import "EnsWilde-Bridging-Header.h"

LSApplicationWorkspace *LSApplicationWorkspaceDefaultWorkspace(void) {
    return [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
}