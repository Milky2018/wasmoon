define range(i32 0, 2) i32 @wasmoon_exception_storage_append(ptr noundef readonly captures(none) %0, i64 noundef %1, ptr noundef readonly captures(none) %2, i32 noundef %3, i64 noundef %4, i64 noundef %5) local_unnamed_addr #0 {
  %7 = alloca %struct.native_exception, align 8
  %8 = alloca ptr, align 8
  %9 = load ptr, ptr %0, align 8
  %10 = getelementptr inbounds nuw i8, ptr %9, i64 8
  %11 = load ptr, ptr %10, align 8
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 20
  %13 = load i32, ptr %12, align 4
  %14 = icmp slt i32 %13, 0
  %15 = zext i32 %13 to i64
  br i1 %14, label %118, label %16

16:                                               ; preds = %6
  %17 = getelementptr inbounds nuw i8, ptr %11, i64 8
  %18 = load i32, ptr %17, align 8
  %19 = getelementptr inbounds nuw i8, ptr %11, i64 12
  %20 = load i32, ptr %19, align 4
  %21 = icmp eq i32 %18, %20
  br i1 %21, label %22, label %35

22:                                               ; preds = %16
  %23 = icmp eq i32 %18, 0
  %24 = sext i32 %18 to i64
  %25 = shl nsw i64 %24, 1
  %26 = select i1 %23, i64 16, i64 %25
  %27 = icmp ugt i64 %26, 2147483647
  br i1 %27, label %118, label %28

28:                                               ; preds = %22
  %29 = load ptr, ptr %11, align 8
  %30 = mul nuw nsw i64 %26, 40
  %31 = tail call ptr @wasmoon_native_realloc(ptr noundef %29, i64 noundef %30) #16
  %32 = icmp eq ptr %31, null
  br i1 %32, label %118, label %33

33:                                               ; preds = %28
  store ptr %31, ptr %11, align 8
  %34 = trunc nuw nsw i64 %26 to i32
  store i32 %34, ptr %19, align 4
  br label %35

35:                                               ; preds = %33, %16
  call void @llvm.lifetime.start.p0(i64 40, ptr nonnull %7) #16
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %7, i8 0, i64 32, i1 false)
  %36 = icmp eq i32 %13, 0
  br i1 %36, label %44, label %37

37:                                               ; preds = %35
  %38 = shl nuw nsw i64 %15, 3
  %39 = tail call ptr @wasmoon_native_malloc(i64 noundef %38) #16
  store ptr %39, ptr %7, align 8
  %40 = icmp eq ptr %39, null
  br i1 %40, label %116, label %41

41:                                               ; preds = %37
  %42 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %43 = load ptr, ptr %42, align 8
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %39, ptr noundef align 1 %43, i64 noundef %38, i1 noundef false) #16
  br label %44

44:                                               ; preds = %41, %35
  %45 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %46 = load i32, ptr %45, align 8
  %47 = getelementptr inbounds nuw i8, ptr %7, i64 32
  store i32 %46, ptr %47, align 8
  %48 = getelementptr inbounds nuw i8, ptr %7, i64 36
  store i32 %13, ptr %48, align 4
  %49 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %50 = load ptr, ptr %49, align 8
  %51 = icmp eq ptr %50, null
  br i1 %51, label %91, label %52

52:                                               ; preds = %44
  %53 = icmp eq i32 %3, 0
  %54 = or i32 %13, %3
  %55 = icmp eq i32 %54, 0
  br i1 %55, label %91, label %56

56:                                               ; preds = %52
  call void @llvm.lifetime.start.p0(i64 8, ptr nonnull %8) #16
  store ptr null, ptr %8, align 8
  %57 = tail call i32 @llvm.umax.i32(i32 %13, i32 1)
  %58 = getelementptr inbounds nuw i8, ptr %7, i64 8
  %59 = call i32 @gc_heap_register_parked_roots(ptr noundef nonnull %50, i32 noundef %57, ptr noundef nonnull %58, ptr noundef nonnull %8) #16
  %60 = icmp eq i32 %59, 0
  br i1 %60, label %99, label %61

61:                                               ; preds = %56
  %62 = getelementptr inbounds i8, ptr %2, i64 -4
  %63 = load i32, ptr %62, align 4
  %64 = icmp eq i32 %63, 0
  %65 = zext nneg i32 %57 to i64
  br label %67

66:                                               ; preds = %79
  br i1 %53, label %90, label %85

67:                                               ; preds = %61, %79
  %68 = phi i64 [ 0, %61 ], [ %83, %79 ]
  %69 = icmp samesign ult i64 %68, %15
  br i1 %69, label %70, label %79

70:                                               ; preds = %67
  br i1 %64, label %75, label %71

71:                                               ; preds = %70
  %72 = getelementptr inbounds nuw i32, ptr %2, i64 %68
  %73 = load i32, ptr %72, align 4
  %74 = icmp eq i32 %73, 0
  br i1 %74, label %79, label %75

75:                                               ; preds = %71, %70
  %76 = load ptr, ptr %7, align 8
  %77 = getelementptr inbounds nuw i64, ptr %76, i64 %68
  %78 = load i64, ptr %77, align 8
  br label %79

79:                                               ; preds = %67, %71, %75
  %80 = phi i64 [ %78, %75 ], [ 0, %71 ], [ 0, %67 ]
  %81 = load ptr, ptr %8, align 8
  %82 = getelementptr inbounds nuw i64, ptr %81, i64 %68
  store i64 %80, ptr %82, align 8
  %83 = add nuw nsw i64 %68, 1
  %84 = icmp eq i64 %83, %65
  br i1 %84, label %66, label %67, !llvm.loop !9

85:                                               ; preds = %66
  %86 = load ptr, ptr %58, align 8
  %87 = load ptr, ptr %0, align 8
  %88 = call i32 @gc_heap_bind_exception_roots(ptr noundef %86, ptr noundef %87, i64 noundef %1) #16
  %89 = icmp eq i32 %88, 0
  br i1 %89, label %99, label %90

90:                                               ; preds = %66, %85
  call void @llvm.lifetime.end.p0(i64 8, ptr nonnull %8) #16
  br label %91

91:                                               ; preds = %90, %52, %44
  %92 = getelementptr inbounds nuw i8, ptr %7, i64 16
  store i64 %4, ptr %92, align 8
  %93 = getelementptr inbounds nuw i8, ptr %7, i64 24
  store i64 %5, ptr %93, align 8
  %94 = load ptr, ptr %11, align 8
  %95 = load i32, ptr %17, align 8
  %96 = add i32 %95, 1
  store i32 %96, ptr %17, align 8
  %97 = sext i32 %95 to i64
  %98 = getelementptr inbounds %struct.native_exception, ptr %94, i64 %97
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(40) %98, ptr noundef nonnull align 8 dereferenceable(40) %7, i64 40, i1 false)
  br label %116

99:                                               ; preds = %56, %85
  call void @llvm.lifetime.end.p0(i64 8, ptr nonnull %8) #16
  %100 = load i32, ptr %48, align 4
  %101 = icmp slt i32 %100, 0
  br i1 %101, label %116, label %102

102:                                              ; preds = %99
  %103 = load ptr, ptr %58, align 8
  %104 = icmp eq ptr %103, null
  br i1 %104, label %106, label %105

105:                                              ; preds = %102
  call void @gc_heap_unregister_parked_roots(ptr noundef nonnull %103) #16
  br label %106

106:                                              ; preds = %105, %102
  %107 = load ptr, ptr %7, align 8
  call void @free(ptr noundef %107)
  %108 = getelementptr inbounds nuw i8, ptr %11, i64 16
  %109 = load ptr, ptr %108, align 8
  %110 = getelementptr inbounds nuw i8, ptr %7, i64 16
  %111 = load i64, ptr %110, align 8
  call void @wasmoon_quota_release(ptr noundef %109, i64 noundef %111) #16
  %112 = getelementptr inbounds nuw i8, ptr %11, i64 24
  %113 = load ptr, ptr %112, align 8
  %114 = getelementptr inbounds nuw i8, ptr %7, i64 24
  %115 = load i64, ptr %114, align 8
  call void @wasmoon_quota_release(ptr noundef %113, i64 noundef %115) #16
  br label %116

116:                                              ; preds = %106, %99, %37, %91
  %117 = phi i32 [ 1, %91 ], [ 0, %37 ], [ 0, %99 ], [ 0, %106 ]
  call void @llvm.lifetime.end.p0(i64 40, ptr nonnull %7) #16
  br label %118

118:                                              ; preds = %28, %22, %6, %116
  %119 = phi i32 [ %117, %116 ], [ 0, %6 ], [ 0, %22 ], [ 0, %28 ]
  ret i32 %119
}
