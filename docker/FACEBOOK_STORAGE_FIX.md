# حل مشكلة فيسبوك 403 مع Supabase Storage

## المشكلة
فيسبوك يعيد خطأ 403 عند محاولة الوصول لصور التخزين:
```
(#100) The media server does not allow downloading of the media due to robots.txt
```

**ملاحظة مهمة:** هذه مشكلة معروفة من 2014 وعادت في 2024. حتى لو كان bucket عام (public)، فيسبوك يحتاج explicit allow في robots.txt.

## الحل المثبت (من تجارب المستخدمين)

بناءً على البحث والمنتديات، الحل هو:
1. وضع `User-agent: facebookexternalhit` في **أول** robots.txt
2. استخدام `Allow: /` فقط بدون Disallow rules بعدها مباشرة
3. عدم الاعتماد على wildcard (*) فقط - فيسبوك يحتاج explicit allow

## الحلول المطبقة

### 1. إصلاح robots.txt ✅ (بناءً على حلول مثبتة من المستخدمين)
تم تحديث `docker/volumes/api/kong.yml` وفقاً للحلول المثبتة:
- **`User-agent: facebookexternalhit` في البداية** مع `Allow: /` فقط
- **لا Disallow rules** في قسم facebookexternalhit (قد تسبب مشاكل)
- تبسيط القواعد - فيسبوك يحتاج explicit allow حتى مع وجود wildcard

**ملاحظة مهمة:** من تجارب المستخدمين، حتى لو كان bucket عام (public)، فيسبوك يحتاج explicit allow في robots.txt. Wildcard (*) وحده لا يكفي.

### 2. التحقق من سياسات قاعدة البيانات (RLS)

**مهم جداً:** تأكد من أن bucket `product-images` لديه سياسة عامة (public policy):

اتصل بقاعدة البيانات وافحص السياسات:

```sql
-- التحقق من وجود bucket
SELECT * FROM storage.buckets WHERE id = 'product-images';

-- التحقق من سياسات RLS على storage.objects
SELECT * FROM pg_policies 
WHERE schemaname = 'storage' 
AND tablename = 'objects'
AND policyname LIKE '%product-images%';
```

إذا لم تكن موجودة، أنشئ سياسة عامة:

```sql
-- إنشاء سياسة للوصول العام لـ product-images
CREATE POLICY "Public Access for product-images"
ON storage.objects FOR SELECT
USING (bucket_id = 'product-images');
```

أو من خلال Supabase Studio:
1. اذهب إلى Storage → product-images
2. افتح Settings → Policies
3. تأكد من وجود سياسة SELECT للجميع (Public)

### 3. إعادة تشغيل Kong

بعد تحديث robots.txt، يجب إعادة تشغيل Kong:

```bash
# في EasyPanel أو Docker
docker restart supabase-kong
```

أو إعادة نشر الـ stack بالكامل في EasyPanel.

### 4. مسح ذاكرة التخزين المؤقت لفيسبوك

استخدم Facebook Sharing Debugger:
1. اذهب إلى: https://developers.facebook.com/tools/debug/
2. أدخل رابط الصورة
3. اضغط "Debug"
4. اضغط "Scrape Again" لإجبار فيسبوك على إعادة فحص robots.txt

### 5. اختبار الوصول

اختبر مع user agent الخاص بفيسبوك:

```bash
curl -i -A "facebookexternalhit/1.1 (+https://www.facebook.com/externalhit_uatext.php)" \
  "https://api.supabase.chattyai.cloud/storage/v1/object/public/product-images/temp_1770732521754_03j49wxed/default/1770732731853_5nr7k.png"
```

يجب أن تحصل على HTTP 200، وليس 403.

## التحقق من الإعدادات

### Kong Configuration ✅
- مسار `/storage/v1/` مفتوح بدون مصادقة
- CORS مفعل
- لا توجد قيود على User-Agent

### robots.txt ✅
- `Allow: /` لفيسبوك bots
- `Allow: /storage/v1/object/public/product-images/` للصور
- `Disallow` فقط لـ API paths

### ما يحتاج للتحقق:
- [ ] سياسات RLS في قاعدة البيانات
- [ ] إعادة تشغيل Kong
- [ ] مسح cache فيسبوك
- [ ] التأكد من أن bucket `product-images` موجود وpublic

## ملاحظات إضافية

إذا استمرت المشكلة بعد تطبيق كل الخطوات:

1. **تحقق من logs Kong:**
   ```bash
   docker logs supabase-kong
   ```

2. **تحقق من logs Storage:**
   ```bash
   docker logs supabase-storage
   ```

3. **اختبر الوصول بدون user agent:**
   ```bash
   curl -i "https://api.supabase.chattyai.cloud/storage/v1/object/public/product-images/..."
   ```
   إذا عمل هذا ولكن فيسبوك لا يعمل، المشكلة في robots.txt cache.

4. **تحقق من EasyPanel WAF:**
   قد يكون هناك Web Application Firewall في EasyPanel يمنع bots.
   تحقق من إعدادات EasyPanel → Security → WAF.
