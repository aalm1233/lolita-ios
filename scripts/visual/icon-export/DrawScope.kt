package androidx.compose.ui.graphics.drawscope
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import java.awt.geom.*
open class DrawStyle
object Fill: DrawStyle()
data class Stroke(val width: Float=1.7f,val cap: String="round",val join: String="round"): DrawStyle()
class Transform(val matrix: AffineTransform) {
    fun rotate(degrees: Float,pivot: Offset=Offset(12f,12f)) { matrix.rotate(Math.toRadians(degrees.toDouble()),pivot.x.toDouble(),pivot.y.toDouble()) }
    fun scale(x: Float,y: Float,pivot: Offset=Offset(12f,12f)) { require(kotlin.math.abs(x)==1f && kotlin.math.abs(y)==1f) { "Non-unit stroke scaling needs an exporter update" };matrix.translate(pivot.x.toDouble(),pivot.y.toDouble());matrix.scale(x.toDouble(),y.toDouble());matrix.translate(-pivot.x.toDouble(),-pivot.y.toDouble()) }
}
class DrawScope {
    var matrix=AffineTransform()
    var clips=mutableListOf<Map<String,Any>>()
    val drawing=mutableListOf<Map<String,Any>>()
    val size=Size(24f,24f)
    fun drawPath(path: Path,color: Color,style: DrawStyle=Fill) {
        val row=mutableMapOf<String,Any>("path" to commands(matrix.createTransformedShape(path.shape)),"clips" to clips.toList())
        if(style is Stroke) row["stroke"]=mapOf("width" to style.width,"cap" to style.cap,"join" to style.join)
        drawing.add(row)
    }
    fun drawLine(color: Color,start: Offset,end: Offset,strokeWidth: Float=1f,cap: String="round") {
        drawPath(Path().apply { moveTo(start.x,start.y);lineTo(end.x,end.y) },color,Stroke(strokeWidth,cap))
    }
    fun drawCircle(color: Color,radius: Float,center: Offset=Offset(12f,12f),style: DrawStyle=Fill) {
        drawOval(color,Offset(center.x-radius,center.y-radius),Size(radius*2,radius*2),style)
    }
    fun drawOval(color: Color,topLeft: Offset,size: Size,style: DrawStyle=Fill) {
        drawPath(Path(Path2D.Float(Ellipse2D.Float(topLeft.x,topLeft.y,size.width,size.height))),color,style)
    }
    fun drawRect(color: Color,topLeft: Offset,size: Size) {
        drawPath(Path(Path2D.Float(Rectangle2D.Float(topLeft.x,topLeft.y,size.width,size.height))),color)
    }
    fun drawRoundRect(color: Color,topLeft: Offset,size: Size,cornerRadius: CornerRadius) {
        drawPath(Path(Path2D.Float(RoundRectangle2D.Float(topLeft.x,topLeft.y,size.width,size.height,cornerRadius.x*2,cornerRadius.y*2))),color)
    }
}
fun DrawScope.withTransform(transformBlock: Transform.()->Unit,drawBlock: DrawScope.()->Unit) {
    val old=matrix;matrix=AffineTransform(old);Transform(matrix).transformBlock()
    try { drawBlock() } finally { matrix=old }
}
fun DrawScope.clipPath(path: Path,clipOp: Int=ClipOp.Intersect,block: DrawScope.()->Unit) {
    val old=clips;clips=clips.toMutableList();clips.add(mapOf("path" to commands(matrix.createTransformedShape(path.shape)),"inverse" to (clipOp==ClipOp.Difference)))
    try { block() } finally { clips=old }
}
fun DrawScope.clipRect(left: Float=0f,top: Float=0f,right: Float=24f,bottom: Float=24f,clipOp: Int=ClipOp.Intersect,block: DrawScope.()->Unit) {
    clipPath(Path(Path2D.Float(Rectangle2D.Float(left,top,right-left,bottom-top))),clipOp,block)
}
