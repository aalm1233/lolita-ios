package com.lolita.app.ui.theme.skin.icon
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
internal enum class SkinIconStyle { SWEET,GOTHIC,CHINESE,CLASSIC,NAVY,COUNTRY,VICTORIAN;
    val stroke: Stroke get()=Stroke(cap=if(this==GOTHIC) "square" else "round",join=if(this==GOTHIC) "miter" else "round")
}
fun json(value: Any?): String = when(value) {
    null -> "null"
    is String -> "\""+value.replace("\\","\\\\").replace("\"","\\\"")+"\""
    is Map<*,*> -> value.entries.joinToString(",","{","}") { json(it.key.toString())+":"+json(it.value) }
    is Iterable<*> -> value.joinToString(",","[","]") { json(it) }
    else -> value.toString()
}
fun main() {
    val result=linkedMapOf<String,Any>()
    for(style in SkinIconStyle.entries) {
        val icons=linkedMapOf<String,Any>()
        for(key in IconKey.entries) {
            val scope=DrawScope();val tint=Color()
            with(scope) { when(key) {
                IconKey.Home,IconKey.Wishlist,IconKey.Outfit,IconKey.Stats,IconKey.Settings -> drawPolishedNavigationIcon(key,style,tint)
                IconKey.Star,IconKey.StarBorder,IconKey.Image,IconKey.Camera,IconKey.AddPhoto,IconKey.Link,IconKey.LinkOff,IconKey.Palette,IconKey.FileOpen,IconKey.CalendarMonth,IconKey.Notifications,IconKey.AttachMoney,IconKey.Category,IconKey.Location,IconKey.Laboratory -> drawPolishedContentIcon(key,style,tint)
                else -> drawPolishedControlIcon(key,style,tint)
            } }
            require(scope.drawing.isNotEmpty()) { "$style/$key is empty" };icons[key.name]=scope.drawing
        }
        result[style.name]=icons
    }
    println(json(result))
}
