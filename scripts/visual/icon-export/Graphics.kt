package androidx.compose.ui.graphics
import java.awt.Shape
import java.awt.geom.*
class Color
object ClipOp { const val Difference = 0; const val Intersect = 1 }
object PathOperation { const val Union = 0 }
class Path(val shape: Path2D.Float = Path2D.Float()) {
    fun moveTo(x: Float,y: Float) { shape.moveTo(x.toDouble(),y.toDouble()) }
    fun lineTo(x: Float,y: Float) { shape.lineTo(x.toDouble(),y.toDouble()) }
    fun quadraticTo(x: Float,y: Float,x2: Float,y2: Float) { shape.quadTo(x.toDouble(),y.toDouble(),x2.toDouble(),y2.toDouble()) }
    fun cubicTo(x: Float,y: Float,x2: Float,y2: Float,x3: Float,y3: Float) { shape.curveTo(x.toDouble(),y.toDouble(),x2.toDouble(),y2.toDouble(),x3.toDouble(),y3.toDouble()) }
    fun close() { shape.closePath() }
    companion object {
        fun combine(op: Int,a: Path,b: Path): Path { require(op == PathOperation.Union); val area=Area(a.shape);area.add(Area(b.shape));return Path(Path2D.Float(area)) }
    }
}
fun commands(shape: Shape): List<List<Any>> {
    val i=shape.getPathIterator(null); val result=mutableListOf<List<Any>>();val p=DoubleArray(6)
    while(!i.isDone) {
        val kind=i.currentSegment(p)
        val (name,count)=when(kind) { 0 -> "M" to 2;1 -> "L" to 2;2 -> "Q" to 4;3 -> "C" to 6;else -> "Z" to 0 }
        result.add(listOf(name)+p.take(count).map { kotlin.math.round(it*100000.0)/100000.0 });i.next()
    }
    return result
}
