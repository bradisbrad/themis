#' Adaptive Synthetic Sampling Approach
#'
#' `step_adasyn` creates a *specification* of a recipe
#'  step that generates synthetic positive instances using ADASYN algorithm.
#'  Using [smotefamily::ADAS()].
#'
#' @inheritParams recipes::step_center
#' @param ... One or more selector functions to choose which
#'  variable is used to sample the data. See [selections()]
#'  for more details. The selection should result in _single
#'  factor variable_. For the `tidy` method, these are not
#'  currently used.
#' @param role Not used by this step since no new variables are
#'  created.
#' @param column A character string of the variable name that will
#'  be populated (eventually) by the `...` selectors.
#' @param neighbors An integer. Number of nearest neighbours that are used
#'  to generate the new examples of the minority class.
#' @param seed An integer that will be used as the seed when
#' applied.
#' @return An updated version of `recipe` with the new step
#'  added to the sequence of existing steps (if any). For the
#'  `tidy` method, a tibble with columns `terms` which is
#'  the variable used to sample.
#'
#' @details
#' All columns in the data are sampled and returned by [juice()]
#'  and [bake()].
#'
#' When used in modeling, users should strongly consider using the
#'  option `skip = TRUE` so that the extra sampling is _not_
#'  conducted outside of the training set.
#'
#' @references He, H., Bai, Y., Garcia, E. and Li, S. 2008. ADASYN: Adaptive
#'  synthetic sampling approach for imbalanced learning. Proceedings of
#'  IJCNN 2008. (IEEE World Congress on Computational Intelligence). IEEE
#'  International Joint Conference. pp.1322-1328.
#'
#' @keywords datagen
#' @concept preprocessing
#' @concept subsampling
#' @export
#' @examples
#' library(recipes)
#' data(okc)
#'
#' sort(table(okc$Class, useNA = "always"))
#'
#' ds_rec <- recipe(Class ~ age + height, data = okc) %>%
#'   step_meanimpute(all_predictors()) %>%
#'   step_adasyn(Class) %>%
#'   prep()
#'
#' table(juice(ds_rec)$Class, useNA = "always")
#'
#' # since `skip` defaults to TRUE, baking the step has no effect
#' baked_okc <- bake(ds_rec, new_data = okc)
#' table(baked_okc$Class, useNA = "always")
#'
#' @importFrom recipes rand_id add_step ellipse_check
step_adasyn <-
  function(recipe, ..., role = NA, trained = FALSE, column = NULL,
           neighbors = 5, skip = TRUE, seed = sample.int(10^5, 1),
           id = rand_id("adasyn")) {

    add_step(recipe,
             step_adasyn_new(
               terms = ellipse_check(...),
               role = role,
               trained = trained,
               column = column,
               neighbors = neighbors,
               skip = skip,
               seed = seed,
               id = id
             ))
  }

#' @importFrom recipes step
step_adasyn_new <-
  function(terms, role, trained, column, neighbors, skip, seed, id) {
    step(
      subclass = "adasyn",
      terms = terms,
      role = role,
      trained = trained,
      column = column,
      neighbors = neighbors,
      skip = skip,
      id = id,
      seed = seed,
      id = id
    )
  }

#' @importFrom recipes bake prep check_type
#' @importFrom dplyr select
#' @importFrom purrr map_lgl
#' @export
prep.step_adasyn <- function(x, training, info = NULL, ...) {

  col_name <- terms_select(x$terms, info = info)
  if (length(col_name) != 1)
    stop("Please select a single factor variable.", call. = FALSE)
  if (!is.factor(training[[col_name]]))
    stop(col_name, " should be a factor variable.", call. = FALSE)
  if (length(levels(training[[col_name]])) != 2)
    stop(col_name, " must only have 2 levels.", call. = FALSE)

  check_type(select(training, -col_name), TRUE)

  if (any(map_lgl(training, ~ any(is.na(.x)))))
    stop("`NA` values are not allowed when using `step_adasyn`", call. = FALSE)

  step_adasyn_new(
    terms = x$terms,
    role = x$role,
    trained = TRUE,
    column = col_name,
    neighbors = x$neighbors,
    skip = x$skip,
    seed = x$seed,
    id = x$id
  )
}

# Turns a binary factor a variable where the majority class is coded as 0 and
# the minority as 1.
response_0_1 <- function(x) {
  ifelse(x == names(sort(table(x)))[1], 1, 0)
}
# Turns 0-1 coded variable back into factor variable
response_0_1_to_org <- function(old, new) {
  ref <- names(sort(table(old)))
  names(ref) <-c("1", "0")
  factor(unname(ref[as.character(new)]))
}

#' @importFrom tibble as_tibble tibble
#' @importFrom withr with_seed
#' @importFrom smotefamily ADAS
#' @importFrom dplyr mutate
#' @importFrom rlang :=
#' @export
bake.step_adasyn <- function(object, new_data, ...) {

  # adasyn with seed for reproducibility
  with_seed(
    seed = object$seed,
    code = {
      new_data0 <-  ADAS(X = select(new_data, -!!object$column),
                         target = new_data[[object$column]],
                         K = object$neighbors)$data
    }
  )

  names(new_data0)[names(new_data0) == "class"] <- object$column
  as_tibble(new_data0[names(new_data)])
}

#' @importFrom recipes printer terms_select
#' @export
print.step_adasyn <-
  function(x, width = max(20, options()$width - 26), ...) {
    cat("adasyn based on ", sep = "")
    printer(x$column, x$terms, x$trained, width = width)
    invisible(x)
  }

#' @rdname step_adasyn
#' @param x A `step_adasyn` object.
#' @importFrom generics tidy
#' @importFrom recipes sel2char is_trained
#' @export
tidy.step_adasyn <- function(x, ...) {
  if (is_trained(x)) {
    res <- tibble(terms = x$column)
  }
  else {
    term_names <- sel2char(x$terms)
    res <- tibble(terms = unname(term_names))
  }
  res$id <- x$id
  res
}