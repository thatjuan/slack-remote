/// Why a paginated read ended.
public enum StopReason: String, Encodable {
    case boundary
    case endOfList = "end_of_list"
    case limit
    case stalled
    case deadline
}
