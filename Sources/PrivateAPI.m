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
// MARK: - bad_query
// Sandbox escape PoC — https://github.com/forcequitOS/bad_query
// Dán toàn bộ nội dung bad_query.c từ repo gốc vào đây.

// Sau khi dán, khai báo 2 hàm để Swift gọi được:
int bad_query(const char *path, bool flag1, void *arg, bool flag2);
void bad_query_release(int handle);
