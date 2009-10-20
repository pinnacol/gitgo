sizes = {}
(1..10).each do |n|
  (1..10).each do |m|
    size = (38*n + 2*m - 95)
    (sizes[(n+m-1)] ||= []) << [n, m, size, size > 0 ? "nest" : "non-nest"]
  end
end

File.open("results.csv", "w") do |io|
  (1..10).each do |i|
    min = sizes[i].min {|a, b| a[2] <=> b[2] }
    max = sizes[i].max {|a, b| a[2] <=> b[2] }
    
    io.puts "#{i} commits"
    io.puts "  #{min.join(',')}"
    io.puts "  #{max.join(',')}"
    io.puts
  end
end

# I conclude from this data that the base directory should be nested
# but the actual comments should not be.  There will usually only be
# one comment per object, and rarely more than say 3.  However, there
# will typically be many objects with comments... far greater than 10.
#
# 1 commits
#   1,1,-55,non-nest
#   1,1,-55,non-nest
# 
# 2 commits
#   1,2,-53,non-nest
#   2,1,-17,non-nest
# 
# 3 commits
#   1,3,-51,non-nest
#   3,1,21,nest
# 
# 4 commits
#   1,4,-49,non-nest
#   4,1,59,nest
# 
# 5 commits
#   1,5,-47,non-nest
#   5,1,97,nest
# 
# 6 commits
#   1,6,-45,non-nest
#   6,1,135,nest
# 
# 7 commits
#   1,7,-43,non-nest
#   7,1,173,nest
# 
# 8 commits
#   1,8,-41,non-nest
#   8,1,211,nest
# 
# 9 commits
#   1,9,-39,non-nest
#   9,1,249,nest
# 
# 10 commits
#   1,10,-37,non-nest
#   10,1,287,nest
