define range(i32 0, 2) i32 @wasmoon_exception_storage_append(ptr noundef readonly captures(none) %0, i64 noundef %1, ptr noundef readonly captures(none) %2, i32 noundef %3, i64 noundef %4, i64 noundef %5) local_unnamed_addr #0 {
  %7 = alloca ptr, align 8
  %8 = alloca ptr, align 8
  %9 = load ptr, ptr %0, align 8
  %10 = getelementptr inbounds nuw i8, ptr %9, i64 8
  %11 = load ptr, ptr %10, align 8
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 20
  %13 = load i32, ptr %12, align 4
  %14 = icmp slt i32 %13, 0
  %15 = zext i32 %13 to i64
  br i1 %14, label %109, label %16

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
  br i1 %27, label %109, label %28

28:                                               ; preds = %22
  %29 = load ptr, ptr %11, align 8
  %30 = mul nuw nsw i64 %26, 40
  %31 = tail call ptr @wasmoon_native_realloc(ptr noundef %29, i64 noundef %30) #16
  %32 = icmp eq ptr %31, null
  br i1 %32, label %109, label %33

33:                                               ; preds = %28
  store ptr %31, ptr %11, align 8
  %34 = trunc nuw nsw i64 %26 to i32
  store i32 %34, ptr %19, align 4
  br label %35

35:                                               ; preds = %33, %16
  %36 = icmp eq i32 %13, 0
  br i1 %36, label %44, label %37

37:                                               ; preds = %35
  %38 = shl nuw nsw i64 %15, 3
  %39 = tail call ptr @wasmoon_native_malloc(i64 noundef %38) #16
  %40 = icmp eq ptr %39, null
  br i1 %40, label %109, label %41

41:                                               ; preds = %37
  %42 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %43 = load ptr, ptr %42, align 8
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %39, ptr noundef align 1 %43, i64 noundef %38, i1 noundef false) #16
  br label %44

44:                                               ; preds = %41, %35
  %45 = phi ptr [ null, %35 ], [ %39, %41 ]
  %46 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %47 = load i32, ptr %46, align 8
  %48 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %49 = load ptr, ptr %48, align 8
  %50 = icmp eq ptr %49, null
  br i1 %50, label %89, label %51

51:                                               ; preds = %44
  %52 = icmp eq i32 %3, 0
  %53 = or i32 %13, %3
  %54 = icmp eq i32 %53, 0
  br i1 %54, label %89, label %55

55:                                               ; preds = %51
  call void @llvm.lifetime.start.p0(i64 8, ptr nonnull %7) #16
  store ptr null, ptr %7, align 8
  %56 = tail call i32 @llvm.umax.i32(i32 %13, i32 1)
  call void @llvm.lifetime.start.p0(i64 8, ptr nonnull %8) #16
  store ptr null, ptr %8, align 8
  %57 = call i32 @gc_heap_register_parked_roots(ptr noundef nonnull %49, i32 noundef %56, ptr noundef nonnull %8, ptr noundef nonnull %7) #16
  %58 = icmp eq i32 %57, 0
  br i1 %58, label %59, label %60

59:                                               ; preds = %55
  call void @llvm.lifetime.end.p0(i64 8, ptr nonnull %8) #16
  call void @llvm.lifetime.end.p0(i64 8, ptr nonnull %7) #16
  br label %104

60:                                               ; preds = %55
  %61 = load ptr, ptr %8, align 8
  %62 = getelementptr inbounds i8, ptr %2, i64 -4
  %63 = load i32, ptr %62, align 4
  %64 = icmp eq i32 %63, 0
  %65 = zext nneg i32 %56 to i64
  br label %67

66:                                               ; preds = %78
  br i1 %52, label %88, label %84

67:                                               ; preds = %60, %78
  %68 = phi i64 [ 0, %60 ], [ %82, %78 ]
  %69 = icmp samesign ult i64 %68, %15
  br i1 %69, label %70, label %78

70:                                               ; preds = %67
  br i1 %64, label %75, label %71

71:                                               ; preds = %70
  %72 = getelementptr inbounds nuw i32, ptr %2, i64 %68
  %73 = load i32, ptr %72, align 4
  %74 = icmp eq i32 %73, 0
  br i1 %74, label %78, label %75

75:                                               ; preds = %71, %70
  %76 = getelementptr inbounds nuw i64, ptr %45, i64 %68
  %77 = load i64, ptr %76, align 8
  br label %78

78:                                               ; preds = %67, %71, %75
  %79 = phi i64 [ %77, %75 ], [ 0, %71 ], [ 0, %67 ]
  %80 = load ptr, ptr %7, align 8
  %81 = getelementptr inbounds nuw i64, ptr %80, i64 %68
  store i64 %79, ptr %81, align 8
  %82 = add nuw nsw i64 %68, 1
  %83 = icmp eq i64 %82, %65
  br i1 %83, label %66, label %67, !llvm.loop !9

84:                                               ; preds = %66
  %85 = load ptr, ptr %0, align 8
  %86 = call i32 @gc_heap_bind_exception_roots(ptr noundef %61, ptr noundef %85, i64 noundef %1) #16
  %87 = icmp eq i32 %86, 0
  br i1 %87, label %101, label %88

88:                                               ; preds = %66, %84
  call void @llvm.lifetime.end.p0(i64 8, ptr nonnull %8) #16
  call void @llvm.lifetime.end.p0(i64 8, ptr nonnull %7) #16
  br label %89

89:                                               ; preds = %88, %51, %44
  %90 = phi ptr [ null, %44 ], [ null, %51 ], [ %61, %88 ]
  %91 = load ptr, ptr %11, align 8
  %92 = load i32, ptr %17, align 8
  %93 = add i32 %92, 1
  store i32 %93, ptr %17, align 8
  %94 = sext i32 %92 to i64
  %95 = getelementptr inbounds %struct.native_exception, ptr %91, i64 %94
  store ptr %45, ptr %95, align 8
  %96 = getelementptr inbounds nuw i8, ptr %95, i64 8
  store ptr %90, ptr %96, align 8
  %97 = getelementptr inbounds nuw i8, ptr %95, i64 16
  store i64 %4, ptr %97, align 8
  %98 = getelementptr inbounds nuw i8, ptr %95, i64 24
  store i64 %5, ptr %98, align 8
  %99 = getelementptr inbounds nuw i8, ptr %95, i64 32
  store i32 %47, ptr %99, align 8
  %100 = getelementptr inbounds nuw i8, ptr %95, i64 36
  store i32 %13, ptr %100, align 4
  br label %109

101:                                              ; preds = %84
  call void @llvm.lifetime.end.p0(i64 8, ptr nonnull %8) #16
  call void @llvm.lifetime.end.p0(i64 8, ptr nonnull %7) #16
  %102 = icmp eq ptr %61, null
  br i1 %102, label %104, label %103

103:                                              ; preds = %101
  call void @gc_heap_unregister_parked_roots(ptr noundef nonnull %61) #16
  br label %104

104:                                              ; preds = %59, %103, %101
  call void @free(ptr noundef %45)
  %105 = getelementptr inbounds nuw i8, ptr %11, i64 16
  %106 = load ptr, ptr %105, align 8
  call void @wasmoon_quota_release(ptr noundef %106, i64 noundef 0) #16
  %107 = getelementptr inbounds nuw i8, ptr %11, i64 24
  %108 = load ptr, ptr %107, align 8
  call void @wasmoon_quota_release(ptr noundef %108, i64 noundef 0) #16
  br label %109

109:                                              ; preds = %89, %37, %104, %28, %22, %6
  %110 = phi i32 [ 0, %6 ], [ 0, %22 ], [ 0, %28 ], [ 1, %89 ], [ 0, %37 ], [ 0, %104 ]
  ret i32 %110
}
